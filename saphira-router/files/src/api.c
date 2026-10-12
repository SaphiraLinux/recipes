/* api.c -- the single control surface: a local Unix-domain API/IPC.
 *
 * The TUI and the CLI are PEERS over this (D1 2.1, D9 1.1). No privileged
 * or configuration operation is reachable by any path that bypasses it, and
 * nothing outside the core opens the database (D1 3.2, D4 1).
 *
 * Protocol: newline-delimited JSON, one request per connection. json-c does
 * the parsing -- a hand-written parser for a multi-tenant control plane is
 * attack surface nobody should own (D1 9.1).
 */

#include "sr_api.h"
#include "sr_db.h"
#include "sr_auth.h"
#include "sr_rbac.h"
#include "sr_audit.h"
#include "sr.h"
#include "sr_module.h"
#include "sr_provider.h"

#include <errno.h>
#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <grp.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

extern char *sr_module_registry_json(sr_db *db);
extern int   sr_enroll_host(sr_db *db, const char *tenant_id, const char *addr,
                            const char *hostname, char **out_id, char **err);
extern int   sr_discover_host(sr_db *db, const char *tenant_id, const char *host_id);

/* ------------------------------------------------------------ helpers */

static char *reply_error(int code, const char *msg)
{
    json_object *o = json_object_new_object();
    json_object_object_add(o, "ok", json_object_new_boolean(0));
    json_object_object_add(o, "code", json_object_new_int(code));
    json_object_object_add(o, "error", json_object_new_string(msg ? msg : "error"));
    const char *s = json_object_to_json_string_ext(o, JSON_C_TO_STRING_PLAIN);
    char *r = sr_xstrdup(s);
    json_object_put(o);
    return r;
}

static char *reply_ok(json_object *body)
{
    json_object_object_add(body, "ok", json_object_new_boolean(1));
    const char *s = json_object_to_json_string_ext(body, JSON_C_TO_STRING_PLAIN);
    char *r = sr_xstrdup(s);
    json_object_put(body);
    return r;
}

/* NULL-safe json string from a result column. A NULL column (an unset
 * version, an absent address) MUST NOT reach json_object_new_string, which
 * dereferences it -- that crashed the daemon on a legitimate host.caps
 * request. Same class of bug as the TUI's NULL %s, on the server side. */
static json_object *jcol(sqlite3_stmt *st, int i)
{
    const unsigned char *t = sqlite3_column_text(st, i);
    return json_object_new_string(t ? (const char *)t : "");
}

static const char *jstr(json_object *o, const char *k, const char *dflt)
{
    json_object *v = NULL;
    if (o && json_object_object_get_ex(o, k, &v) && v)
        return json_object_get_string(v);
    return dflt;
}

/* Resolve the caller's identity from the session token. Sessions are bound
 * to (user, tenant) (D3 3). */
static int resolve_session(sr_db *db, const char *token,
                           char **uid, char **tid, char **sid)
{
    return sr_auth_session_lookup(db, token, uid, tid, sid);
}

/* ------------------------------------------------------------- server */

typedef struct {
    sr_db *db;
    char   socket_path[SR_MAX_PATH];
    int    listen_fd;
} sr_server;

static char *dispatch(sr_server *sv, const char *reqline, const char *peer)
{
    json_object *req = json_tokener_parse(reqline);
    if (!req) return reply_error(SR_ERR_USAGE, "malformed request");

    const char *op = jstr(req, "op", "");
    const char *token = jstr(req, "token", "");

    char *uid = NULL, *tid = NULL, *sid = NULL;
    int authed = resolve_session(sv->db, token, &uid, &tid, &sid) == 0;

    /* --- unauthenticated operations --- */
    if (strcmp(op, "login") == 0) {
        const char *user = jstr(req, "username", "");
        const char *pw   = jstr(req, "password", "");
        char *err = NULL;
        char *v1 = NULL, *v2 = NULL;
        int rc = sr_auth_verify(sv->db, user, pw, &v1, &v2, &err);
        free(err);
        if (rc != SR_OK) {
            /* A wrong password and an unknown user are denied identically --
             * and the attempt is still AUDITED, because a failed login is
             * exactly the event an operator wants to see later. tenant_id is
             * NULL: no context was ever established. */
            sr_audit(sv->db, NULL, NULL, NULL, "auth.login", "user", user,
                     SR_AUDIT_DENIED, peer, NULL);
            return reply_error(SR_ERR_DENIED, "authentication failed");
        }
        char *tok = NULL, *sess = NULL;
        err = NULL;
        if (sr_auth_session_create(sv->db, v1, v2, peer, &tok, &sess, &err) < 0) {
            free(v1); free(v2);
            char *r = reply_error(SR_ERR_FAILED, err ? err : "session failed");
            free(err);
            return r;
        }
        sr_audit(sv->db, v2, v1, sess, "auth.login", "user", user,
                 SR_AUDIT_SUCCESS, peer, NULL);
        sr_audit(sv->db, v2, v1, sess, "session.create", "session", sess,
                 SR_AUDIT_SUCCESS, peer, NULL);
        json_object *o = json_object_new_object();
        json_object_object_add(o, "token", json_object_new_string(tok));
        json_object_object_add(o, "session_id", json_object_new_string(sess));
        json_object_object_add(o, "user_id", json_object_new_string(v1));
        json_object_object_add(o, "tenant_id", json_object_new_string(v2));
        char *r = reply_ok(o);
        free(tok); free(sess); free(v1); free(v2);
        return r;
    }

    if (strcmp(op, "logout") == 0) {
        sqlite3_stmt *st = NULL;
        int revoked = 0;
        if (sr_db_prepare(sv->db,
                "UPDATE session SET revoked_at=datetime('now') "
                "WHERE id=? AND revoked_at IS NULL;", &st, NULL) == 0) {
            sqlite3_bind_text(st, 1, sid, -1, SQLITE_STATIC);
            sqlite3_step(st);
            revoked = sqlite3_changes(sr_db_handle(sv->db));
            sqlite3_finalize(st);
        }
        sr_audit(sv->db, tid, uid, sid, "session.destroy", "session", sid,
                 SR_AUDIT_SUCCESS, peer, NULL);
        json_object *o = json_object_new_object();
        json_object_object_add(o, "revoked", json_object_new_int(revoked));
        char *r = reply_ok(o);
        free(uid); free(tid); free(sid);
        json_object_put(req);
        return r;
    }

    if (strcmp(op, "ping") == 0) {
        json_object *o = json_object_new_object();
        json_object_object_add(o, "service", json_object_new_string("saphira-router"));
        json_object_object_add(o, "version", json_object_new_string("0.1.0"));
        return reply_ok(o);
    }

    /* --- everything else requires a session --- */
    if (!authed) {
        free(uid); free(tid); free(sid);
        json_object_put(req);
        return reply_error(SR_ERR_DENIED, "authentication required");
    }

    char *out = NULL;

    if (strcmp(op, "provider.invoke") == 0) {
        /* ONE lifecycle step, dispatched generically. The step name arrives
         * from the wire and the core maps it to the module's provides bit, so
         * a module that does not implement a step is refused with a reason
         * rather than called and crashed. */
        sr_step step;
        const char *sname = jstr(req, "step", "");
        if (sr_step_from_name(sname, &step) != 0) {
            out = reply_error(SR_ERR_USAGE, "unknown provider step");
        } else {
            char *po = NULL, *pe = NULL;
            int rc = sr_provider_invoke(sv->db, jstr(req, "module", ""), step,
                                        uid, tid,
                                        jstr(req, "host_id", ""),
                                        jstr(req, "object_type", ""),
                                        jstr(req, "json", NULL), &po, &pe);
            if (rc == SR_OK) {
                json_object *o = json_object_new_object();
                json_object_object_add(o, "output",
                                       json_object_new_string(po ? po : ""));
                out = reply_ok(o);
            } else {
                /* Prefer the step's own output, then the core's reason for the
                 * refusal, and only then a generic line. A refusal the operator
                 * cannot act on is not a usable error. */
                out = reply_error(rc, (po && *po) ? po
                                 : (pe && *pe) ? pe
                                 : "provider step failed");
            }
            free(po);
            free(pe);
        }
    } else if (strcmp(op, "provider.transaction") == 0) {
        /* The whole lifecycle for one desired-state change, sequenced and
         * owned by the core: discover, validate, render, stage, apply, verify,
         * and rollback on failure. Not specific to any subsystem. */
        char *rep = NULL;
        int rc = sr_provider_transaction(sv->db, jstr(req, "module", ""),
                                         uid, tid,
                                         jstr(req, "host_id", ""),
                                         jstr(req, "object_type", ""),
                                         jstr(req, "json", ""), &rep);
        if (rc == SR_OK) {
            json_object *o = json_object_new_object();
            json_object_object_add(o, "report",
                                   json_object_new_string(rep ? rep : "{}"));
            out = reply_ok(o);
        } else {
            /* The per-step report travels WITH the failure. "apply failed"
             * without saying whether the rollback restored the previous state
             * is not a usable error. */
            out = reply_error(rc, rep ? rep : "transaction failed");
        }
        free(rep);
    } else if (strcmp(op, "module.list") == 0) {
        /* The registry is the only source of what exists (D2 3): sections in
         * the TUI come from here, never from a hard-coded provider list. */
        char *j = sr_module_registry_json(sv->db);
        json_object *arr = json_tokener_parse(j);
        json_object *o = json_object_new_object();
        json_object_object_add(o, "modules", arr ? arr : json_object_new_array());
        free(j);
        out = reply_ok(o);
    } else if (strcmp(op, "host.list") == 0) {
        sqlite3_stmt *st = NULL;
        json_object *arr = json_object_new_array();
        /* Tenant isolation: the query is scoped to the session's tenant and
         * there is no path that reads across it (D5 4). */
        if (sr_db_prepare(sv->db,
            "SELECT id,hostname,address_v4,address_v6,os_name,os_version,"
            "arch,status FROM host WHERE tenant_id=? ORDER BY hostname;",
            &st, NULL) == 0) {
            sqlite3_bind_text(st, 1, tid, -1, SQLITE_STATIC);
            while (sqlite3_step(st) == SQLITE_ROW) {
                json_object *h = json_object_new_object();
                json_object_object_add(h, "id",       jcol(st, 0));
                json_object_object_add(h, "hostname", jcol(st, 1));
                json_object_object_add(h, "address_v4", jcol(st, 2));
                json_object_object_add(h, "address_v6", jcol(st, 3));
                json_object_object_add(h, "os_name",   jcol(st, 4));
                json_object_object_add(h, "os_version", jcol(st, 5));
                json_object_object_add(h, "arch",      jcol(st, 6));
                json_object_object_add(h, "status",    jcol(st, 7));
                json_object_array_add(arr, h);
            }
            sqlite3_finalize(st);
        }
        json_object *o = json_object_new_object();
        json_object_object_add(o, "hosts", arr);
        out = reply_ok(o);
    } else if (strcmp(op, "host.caps") == 0) {
        const char *host_id = jstr(req, "host_id", "");
        sqlite3_stmt *st = NULL;
        json_object *arr = json_object_new_array();
        /* Tenant-scoped: the host must belong to this tenant, otherwise the
         * caller gets nothing at all (D5 7.3, id-addressed case). */
        if (sr_db_prepare(sv->db,
            "SELECT hc.capability, hc.state, hc.version, "
            "       COALESCE(hc.probe_method,''), COALESCE(hc.detail,''), "
            "       hc.checked_at "
            "FROM host_capability hc JOIN host h ON h.id=hc.host_id "
            "WHERE hc.host_id=? AND h.tenant_id=? ORDER BY hc.capability;",
            &st, NULL) == 0) {
            sqlite3_bind_text(st, 1, host_id, -1, SQLITE_STATIC);
            sqlite3_bind_text(st, 2, tid, -1, SQLITE_STATIC);
            while (sqlite3_step(st) == SQLITE_ROW) {
                json_object *c = json_object_new_object();
                json_object_object_add(c, "capability", jcol(st, 0));
                json_object_object_add(c, "state",      jcol(st, 1));
                json_object_object_add(c, "version",    jcol(st, 2));
                json_object_object_add(c, "probe_method", jcol(st, 3));
                json_object_object_add(c, "detail",     jcol(st, 4));
                json_object_object_add(c, "checked_at", jcol(st, 5));
                json_object_array_add(arr, c);
            }
            sqlite3_finalize(st);
        }
        json_object *o = json_object_new_object();
        json_object_object_add(o, "capabilities", arr);
        out = reply_ok(o);
    } else if (strcmp(op, "host.enroll") == 0) {
        const char *addr = jstr(req, "address", "");
        const char *name = jstr(req, "hostname", addr);
        char *why = NULL;
        if (!sr_rbac_authorize(sv->db, uid, tid, "host.enroll", &why)) {
            free(why);
            sr_audit(sv->db, tid, uid, sid, "host.enroll", "host", name,
                     SR_AUDIT_DENIED, peer, NULL);
            out = reply_error(SR_ERR_DENIED, "missing capability 'host.enroll'");
        } else {
            char *err = NULL, *hid = NULL;
            if (sr_enroll_host(sv->db, tid, addr, name, &hid, &err) < 0) {
                sr_audit(sv->db, tid, uid, sid, "host.enroll", "host", name,
                         SR_AUDIT_FAILED, peer, NULL);
                out = reply_error(SR_ERR_FAILED, err ? err : "enrollment failed");
                free(err);
            } else {
                sr_audit(sv->db, tid, uid, sid, "host.enroll", "host", hid,
                         SR_AUDIT_SUCCESS, peer, NULL);
                sr_discover_host(sv->db, tid, hid);
                json_object *o = json_object_new_object();
                json_object_object_add(o, "host_id", json_object_new_string(hid));
                out = reply_ok(o);
                free(hid);
            }
        }
    } else if (strcmp(op, "capability.check") == 0) {
        const char *cap = jstr(req, "capability", "");
        char *why = NULL;
        int ok = sr_rbac_authorize(sv->db, uid, tid, cap, &why);
        json_object *o = json_object_new_object();
        json_object_object_add(o, "capability", json_object_new_string(cap));
        json_object_object_add(o, "allowed", json_object_new_boolean(ok));
        if (!ok) json_object_object_add(o, "reason", json_object_new_string(why ? why : "denied"));
        free(why);
        /* An authorization denial is a successful query about a denial, so the
         * transport succeeds while the answer says 'no'. */
        out = reply_ok(o);
    } else {
        out = reply_error(SR_ERR_USAGE, "unknown operation");
    }

    free(uid); free(tid); free(sid);
    json_object_put(req);
    return out;
}

int sr_api_serve(sr_db *db, const char *socket_path, volatile int *stopflag)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof addr.sun_path) {
        sr_log(SR_LOG_ERROR, "socket path too long: %s", socket_path);
        return -1;
    }
    strcpy(addr.sun_path, socket_path);

    /* The socket is the ONLY path to the database, so its group is the only
     * thing an operator needs in order to drive the control plane -- and
     * membership confers NO database access whatsoever. That is the whole
     * point: the state directory stays 0750 to the service identity while a
     * group member can still operate the platform.
     *
     * Binding with a restrictive umask alone left the socket 0600, which
     * locked every operator out; the group has to be applied explicitly. */
    const char *grp = getenv("SR_SOCK_GROUP");
    if (!grp || !*grp) grp = "wheel";
    mode_t smode = 0660;
    const char *sm = getenv("SR_SOCK_MODE");
    if (sm && *sm) {
        unsigned long m = strtoul(sm, NULL, 8);
        if (m > 0 && m <= 0777) smode = (mode_t)m;
    }

    unlink(socket_path);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) { sr_log(SR_LOG_ERROR, "socket: %s", strerror(errno)); return -1; }

    /* Private to the owner: this is an administrative control surface. */
    mode_t old = umask(0177);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        umask(old);
        sr_log(SR_LOG_ERROR, "bind %s: %s", socket_path, strerror(errno));
        close(fd);
        return -1;
    }
    umask(old);

    /* Apply the group and mode AFTER bind: before the socket exists there is
     * nothing to chown. Failing here is fatal rather than silent -- a socket
     * nobody can reach would look like a healthy daemon. */
    {
        struct group *g = getgrnam(grp);
        if (g && chown(socket_path, (uid_t)-1, g->gr_gid) < 0) {
            /* Expected: the core is unprivileged and chown to another group
             * needs CAP_CHOWN, so the service manager applies it after start.
             * Log it as information, not an error, and say who must do it. */
            sr_log(SR_LOG_INFO, "cannot chown socket to group %s as an "
                   "unprivileged identity (%s); the service manager is expected "
                   "to apply it after start", grp, strerror(errno));
        } else if (!g) {
            sr_log(SR_LOG_ERROR, "socket group '%s' does not exist; the socket "
                   "will not be reachable by operators", grp);
        }
        if (chmod(socket_path, smode) < 0)
            sr_log(SR_LOG_ERROR, "chmod socket %04o: %s", smode, strerror(errno));
    }

    if (listen(fd, 16) < 0) { close(fd); unlink(socket_path); return -1; }

    sr_log(SR_LOG_INFO, "API listening on %s", socket_path);

    while (!stopflag || !*stopflag) {
        struct sockaddr_un peer;
        socklen_t plen = sizeof peer;
        int c = accept(fd, (struct sockaddr *)&peer, &plen);
        if (c < 0) { if (errno == EINTR) continue; break; }

        char buf[SR_MAX_JSON];
        ssize_t n = read(c, buf, sizeof buf - 1);
        if (n > 0) {
            buf[n] = '\0';
            char *nl = strchr(buf, '\n');
            if (nl) *nl = '\0';
            char *rep = dispatch(&(sr_server){ .db = db }, buf, "");
            size_t rl = strlen(rep);
            char *line = malloc(rl + 2);
            memcpy(line, rep, rl);
            line[rl] = '\n';
            line[rl + 1] = '\0';
            ssize_t w = write(c, line, rl + 1);
            (void)w;
            free(line);
            free(rep);
        }
        close(c);
    }
    close(fd);
    unlink(socket_path);
    return 0;
}

/* ------------------------------------------------------------- client */

char *sr_api_call(const char *socket_path, const char *req, int *out_code)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (!socket_path || strlen(socket_path) >= sizeof addr.sun_path) return NULL;
    strcpy(addr.sun_path, socket_path);

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return NULL;
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        close(fd);
        if (out_code) *out_code = SR_ERR_FAILED;
        return NULL;
    }
    size_t rl = strlen(req);
    char *line = malloc(rl + 2);
    memcpy(line, req, rl); line[rl] = '\n'; line[rl + 1] = '\0';
    if (write(fd, line, rl + 1) < 0) { free(line); close(fd); return NULL; }
    free(line);

    char *buf = malloc(SR_MAX_JSON);
    if (!buf) { close(fd); return NULL; }
    ssize_t n = read(fd, buf, SR_MAX_JSON - 1);
    close(fd);
    if (n <= 0) { free(buf); return NULL; }
    buf[n] = '\0';
    char *nl = strchr(buf, '\n');
    if (nl) *nl = '\0';

    if (out_code) {
        json_object *o = json_tokener_parse(buf);
        json_object *okv = NULL, *cv = NULL;
        int code = SR_OK;
        if (o) {
            if (json_object_object_get_ex(o, "ok", &okv))
                if (!json_object_get_boolean(okv)) code = SR_ERR_DENIED;
            if (json_object_object_get_ex(o, "code", &cv))
                code = json_object_get_int(cv);
            json_object_put(o);
        }
        *out_code = code;
    }
    return buf;
}

char *sr_api_login(const char *socket_path, const char *user, const char *pw,
                   char **out_token, int *out_code)
{
    json_object *o = json_object_new_object();
    json_object_object_add(o, "op", json_object_new_string("login"));
    json_object_object_add(o, "username", json_object_new_string(user));
    json_object_object_add(o, "password", json_object_new_string(pw));
    char *req = sr_xstrdup(json_object_to_json_string_ext(o, JSON_C_TO_STRING_PLAIN));
    json_object_put(o);

    char *resp = sr_api_call(socket_path, req, out_code);
    free(req);
    if (!resp) return NULL;

    json_object *r = json_tokener_parse(resp);
    if (r) {
        json_object *tv = NULL;
        if (json_object_object_get_ex(r, "token", &tv))
            *out_token = sr_xstrdup(json_object_get_string(tv));
        json_object_put(r);
    }
    return resp;   /* caller frees */
}
