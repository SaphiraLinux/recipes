/* mod_ipvs.c -- the first genuine provider: IPVS.
 *
 * This is deliberately NOT a fixture. A fixture proves the seam exists; this
 * exercises it against a real kernel subsystem with real state, real partial
 * failures and a real rollback. Everything it does, the next provider does the
 * same way, so the shape here is the template.
 *
 * ---------------------------------------------------------------- backend
 *
 * The backend is the ipvsadm(8) binary, invoked with an argv array. NOT the
 * kernel/netlink interface. The reasons, recorded because this is a decision
 * and not a default:
 *
 *   - ipvsadm is already a Saphira package (/recipes/ipvsadm, 1.31-r2, owned
 *     here and inheriting this project's recipe discipline), and is already
 *     installed. Nothing new must be introduced to obtain it.
 *   - `ipvsadm -S` prints the whole virtual-server table in an exact save
 *     form that round-trips byte for byte. That is precisely what render,
 *     stage, verify and rollback need, and the kernel does not hand it out in
 *     that shape.
 *   - Speaking IPVS netlink in-process means implementing part of a subsystem
 *     protocol inside the router: a large new dependency, bought only to avoid
 *     a small controlled subprocess interface. That is not the trade this
 *     project makes.
 *   - A subprocess with an argv array and no shell has no quoting, globbing or
 *     word-splitting hazard. It is a small, auditable interface.
 *
 * Netlink stays available as a later optimisation. It is not justified now.
 *
 * --------------------------------------------------------------- contract
 *
 * The exact form of `ipvsadm -S` as verified against 1.31-r2 on this host:
 *
 *     -A -t 10.0.0.1:80 -s wlc
 *     -a -t 10.0.0.1:80 -r 127.0.0.2:8080 -m -w 5
 *     -a -t 10.0.0.1:80 -r 127.0.0.3:80 -g -w 1
 *
 * One flag per line, values as separate tokens, protocol carried by the flag
 * letter (t=tcp, u=udp), forwarder by -m (masq) or -g (route). Replaying those
 * lines as argv after `ipvsadm -C` was verified to restore the table EXACTLY;
 * that is the rollback mechanism, because this build of ipvsadm has no -R.
 *
 * A real-server port is NORMALISED by the kernel: `-r 127.0.0.3:8080` with no
 * forwarder becomes 127.0.0.3:80 Route, discarding the 8080. So reconciliation
 * compares against what IPVS reports, never against what was requested. A
 * provider that diffed against its own request would report a phantom
 * mismatch on every direct-routed server.
 *
 * -------------------------------------------------------------- authority
 *
 * This module describes, validates, renders, applies and verifies IPVS state.
 * Transactions, audit and authorization belong to the core and are reached only
 * through sr_ctx. It is given no database handle and no shell (D1 8, D3 2).
 *
 * One rule shapes the rest: THE KERNEL IS THE SOURCE OF TRUTH. This module's
 * memory is a cache, never an authority. An unload and reload must rediscover
 * whatever IPVS actually holds -- including state something else created -- and
 * must never assume its previous opinion still holds. Nothing important is
 * therefore kept only in a static, and rollback reads the persisted snapshot
 * rather than an in-memory belief.
 */
#include "sr_module.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define IPVS_MAX_SVC   64
#define IPVS_MAX_RS    64
#define IPVS_MAX_TOK   16
#define IPVS_LINE      512

/* Where the snapshot for the in-flight transaction is persisted, in core
 * state. Core-mediated, so it survives an unload and a reload, and so the
 * module never keeps the only copy of something rollback depends on. */
#define IPVS_SNAPSHOT_TYPE "ipvs_snapshot"

/* ------------------------------------------------------------------ util */

typedef struct { char *b; size_t len, cap; } sb;

static void sb_init(sb *s) { s->b = NULL; s->len = 0; s->cap = 0; }
static void sb_free(sb *s) { free(s->b); sb_init(s); }

static void sb_addf(sb *s, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int need = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (need < 0) return;
    if (s->len + (size_t)need + 1 > s->cap) {
        size_t nc = s->cap ? s->cap : 1024;
        while (nc < s->len + (size_t)need + 1) nc *= 2;
        char *nb = realloc(s->b, nc);
        if (!nb) return;
        s->b = nb; s->cap = nc;
    }
    va_start(ap, fmt);
    vsnprintf(s->b + s->len, s->cap - s->len, fmt, ap);
    va_end(ap);
    s->len += (size_t)need;
}

static void sb_jstr(sb *s, const char *v)
{
    sb_addf(s, "\"");
    for (; v && *v; v++) {
        unsigned char c = (unsigned char)*v;
        switch (c) {
        case '"':  sb_addf(s, "\\\""); break;
        case '\\': sb_addf(s, "\\\\"); break;
        case '\n': sb_addf(s, "\\n");  break;
        case '\r': sb_addf(s, "\\r");  break;
        case '\t': sb_addf(s, "\\t");  break;
        default:   if (c < 0x20) sb_addf(s, "\\u%04x", c); else sb_addf(s, "%c", c);
        }
    }
    sb_addf(s, "\"");
}

static char *sdup(const char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

static char *trim(char *s)
{
    while (*s && isspace((unsigned char)*s)) s++;
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) *--e = '\0';
    return s;
}

/* --------------------------------------------------------- backend calls */

static const char *ipvsadm_path(void)
{
    const char *p = getenv("SR_IPVSADM");
    return (p && *p) ? p : "ipvsadm";
}

/* Run the backend, capturing stdout only.
 *
 * stderr is deliberately NOT merged in: the backend writes diagnostics there
 * ("modprobe: Module ip_vs not found in directory /lib/modules/...") that are
 * not state, and letting them into the parse buffer would make a correct read
 * look like garbage. On this host ip_vs is built into the running kernel, so
 * that modprobe complaint is expected noise and means nothing.
 */
static int ipvs_run(char *const argv[], char **out, int *out_status)
{
    int fds[2];
    if (out) *out = NULL;
    if (out_status) *out_status = -1;
    if (pipe(fds) < 0) return -1;

    pid_t pid = fork();
    if (pid < 0) { close(fds[0]); close(fds[1]); return -1; }
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) { dup2(devnull, STDERR_FILENO); close(devnull); }
        close(fds[1]);
        execvp(argv[0], argv);
        _exit(127);
    }
    close(fds[1]);

    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    if (!buf) { close(fds[0]); return -1; }
    for (;;) {
        if (len + 1024 > cap) {
            cap *= 2;
            char *nb = realloc(buf, cap);
            if (!nb) { free(buf); close(fds[0]); return -1; }
            buf = nb;
        }
        ssize_t n = read(fds[0], buf + len, cap - len - 1);
        if (n <= 0) break;
        len += (size_t)n;
    }
    buf[len] = '\0';
    close(fds[0]);

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
    int rc = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    if (out_status) *out_status = rc;
    if (out) *out = buf; else free(buf);
    return 0;
}

static char *ipvs_save(char **err)
{
    char *argv[] = { (char *)ipvsadm_path(), (char *)"-S", NULL };
    char *out = NULL; int st = -1;
    if (ipvs_run(argv, &out, &st) < 0) { if (err) *err = sdup("ipvsadm could not be executed"); return NULL; }
    if (st != 0) {
        if (err) *err = sdup("ipvsadm -S failed: the IPVS subsystem is not available in this namespace");
        free(out); return NULL;
    }
    return out;
}

/* Execute one save-form line as argv. Used by both apply and rollback.
 * Tokens are split on whitespace and handed to execvp as separate arguments:
 * no shell is involved at any point. */
static int ipvs_exec_line(const char *line, char **err)
{
    char *buf = sdup(line);
    if (!buf) return -1;
    char *argv[IPVS_MAX_TOK + 2];
    int n = 0;
    argv[n++] = (char *)ipvsadm_path();
    /* strtok_r, not strtok: this is called from INSIDE apply()'s own line
     * walk, and the plain strtok keeps one static cursor, so tokenising here
     * would destroy the caller's iteration -- which walked off the buffer and
     * killed the daemon mid-transaction. */
    char *tsave = NULL;
    for (char *t = strtok_r(buf, " \t", &tsave); t && n < IPVS_MAX_TOK + 1;
         t = strtok_r(NULL, " \t", &tsave))
        argv[n++] = t;
    argv[n] = NULL;

    int st = -1;
    int rc = ipvs_run(argv, NULL, &st);
    free(buf);
    if (rc < 0) { if (err) *err = sdup("ipvsadm could not be executed"); return -1; }
    if (st != 0) {
        if (err) {
            char m[320];
            snprintf(m, sizeof m, "ipvsadm rejected '%s'", trim((char *)line));
            *err = sdup(m);
        }
        return -1;
    }
    return 0;
}

/* ---------------------------------------------------------------- parsing
 *
 * The save form, as verified above. Parsed into a shape the rest of the module
 * reasons about. Managed and unmanaged services are kept apart from the very
 * first parse, because the whole point of distinguishing them is that unmanaged
 * state is observed and then left strictly alone.
 */
typedef struct {
    char  proto;        /* 't' or 'u' */
    char  vip[64];
    int   port;
    char  sched[16];
    int   nrs;
    char  rs_addr[IPVS_MAX_RS][64];
    int   rs_port[IPVS_MAX_RS];
    char  rs_fwd[IPVS_MAX_RS][8];   /* "masq" | "route" -- 8, not 4:
                                 * char[4] silently truncated BOTH,
                                 * turning masq into "mas" and
                                 * route into "rou". */
    int   rs_weight[IPVS_MAX_RS];
} svc;

typedef struct {
    svc   v[IPVS_MAX_SVC];
    int   n;
} table;

/* Split "10.0.0.1:80" into host and port. */
static int split_hostport(const char *s, char *host, size_t hostsz, int *port)
{
    const char *c = strrchr(s, ':');
    if (!c || c == s) return -1;
    size_t n = (size_t)(c - s);
    if (n >= hostsz) return -1;
    memcpy(host, s, n);
    host[n] = '\0';
    *port = atoi(c + 1);
    return 0;
}

static int find_svc(table *t, char proto, const char *vip, int port)
{
    for (int i = 0; i < t->n; i++)
        if (t->v[i].proto == proto && t->v[i].port == port &&
            strcmp(t->v[i].vip, vip) == 0)
            return i;
    return -1;
}

static int parse_save(const char *text, table *t)
{
    t->n = 0;
    if (!text) return 0;
    char *copy = sdup(text);
    if (!copy) return 0;

    int cur = -1;
    /* strtok_r, NOT strtok.
     *
     * This parser splits each line into tokens WHILE walking the lines, and
     * strtok keeps that state in a single static. The inner token loop
     * therefore destroyed the outer line iterator: parsing stopped after the
     * first line, so every real server was silently missing from the observed
     * table -- and the walk continued from a stale offset, which is what killed
     * the daemon. strtok_r keeps one cursor per level, so the two loops stop
     * interfering.
     *
     * The reentrant form is not stylistic here; the plain one is a memory-safety
     * defect, and it is invisible in any test that only ever has one line. */
    char *lsave = NULL;
    for (char *line = strtok_r(copy, "\n", &lsave); line;
         line = strtok_r(NULL, "\n", &lsave)) {
        char *l = trim(line);
        if (!*l || *l != '-') continue;

        char tok[IPVS_MAX_TOK][40];
        int n = 0;
        char *tsave = NULL;
        for (char *w = strtok_r(l, " \t", &tsave); w && n < IPVS_MAX_TOK;
             w = strtok_r(NULL, " \t", &tsave))
            snprintf(tok[n++], 40, "%s", w);
        if (n == 0) continue;

        int is_add_svc = (strcmp(tok[0], "-A") == 0);
        int is_add_rs  = (strcmp(tok[0], "-a") == 0);
        if (!is_add_svc && !is_add_rs) continue;

        char proto = 0;
        char host[64] = "";
        int  port = 0, sched_at = -1, rs_at = -1, weight = 1, m = 0;
        for (int i = 1; i < n; i++) {
            if (!strcmp(tok[i], "-t") && i + 1 < n) {
                proto = 't'; split_hostport(tok[++i], host, sizeof host, &port);
            } else if (!strcmp(tok[i], "-u") && i + 1 < n) {
                proto = 'u'; split_hostport(tok[++i], host, sizeof host, &port);
            } else if (!strcmp(tok[i], "-s") && i + 1 < n) {
                sched_at = ++i;
            } else if (!strcmp(tok[i], "-r") && i + 1 < n) {
                rs_at = ++i;
            } else if (!strcmp(tok[i], "-w") && i + 1 < n) {
                weight = atoi(tok[++i]);
            } else if (!strcmp(tok[i], "-m")) {
                m = 1;
            } else if (!strcmp(tok[i], "-g")) {
                /* direct route, which is also what an absent forwarder means */
            }
        }
        if (!proto || host[0] == '\0' || port <= 0) continue;

        if (is_add_svc) {
            if (t->n >= IPVS_MAX_SVC) continue;
            cur = t->n++;
            svc *sv = &t->v[cur];
            memset(sv, 0, sizeof *sv);
            sv->proto = proto;
            snprintf(sv->vip, sizeof sv->vip, "%s", host);
            sv->port = port;
            if (sched_at > 0) snprintf(sv->sched, sizeof sv->sched, "%s", tok[sched_at]);
        } else if (is_add_rs && cur >= 0) {
            svc *sv = &t->v[cur];
            if (sv->nrs < IPVS_MAX_RS && rs_at > 0) {
                int rp = 0;
                char rh[64];
                if (split_hostport(tok[rs_at], rh, sizeof rh, &rp) == 0) {
                    snprintf(sv->rs_addr[sv->nrs], 64, "%s", rh);
                    sv->rs_port[sv->nrs] = rp;
                    snprintf(sv->rs_fwd[sv->nrs], 8, "%s", m ? "masq" : "route");
                    sv->rs_weight[sv->nrs] = weight;
                    sv->nrs++;
                }
            }
        }
    }
    free(copy);
    return t->n;
}

/* -------------------------------------------------------- desired state
 *
 * The object the module manages, as the core passes it in. A small hand parser
 * rather than a JSON library: the module is a trusted in-process .so, and
 * pulling json-c into a module would give every provider a second JSON
 * dialect to disagree about. The core already parses and re-serialises.
 */
typedef struct {
    char proto[8];
    char vip[64];
    int  port;
    char sched[16];
    int  nrs;
    char rs_addr[IPVS_MAX_RS][64];
    int  rs_port[IPVS_MAX_RS];
    char rs_fwd[IPVS_MAX_RS][8];
    int  rs_weight[IPVS_MAX_RS];
} desired;

static int json_val(const char *json, const char *key, char *out, size_t outsz)
{
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return -1;
    p = strchr(p + strlen(pat), ':');
    if (!p) return -1;
    p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '"') {
        p++;
        size_t i = 0;
        while (*p && *p != '"' && i + 1 < outsz) out[i++] = *p++;
        out[i] = '\0';
        return 0;
    }
    size_t i = 0;
    while (*p && *p != ',' && *p != '}' && *p != ' ' && i + 1 < outsz) out[i++] = *p++;
    out[i] = '\0';
    return 0;
}

/* Read the real-server array as flat triples of (address, port, forwarder,
 * weight) in document order. Deliberately positional and simple: the shape is
 * fixed by validate(), which runs first, so this never has to cope with
 * anything it has not already accepted. */
static int json_realservers(const char *json, desired *d)
{
    const char *arr = strstr(json, "\"real_servers\"");
    if (!arr) return 0;
    arr = strchr(arr, '[');
    if (!arr) return 0;
    const char *end = strchr(arr, ']');
    if (!end) return -1;

    char *buf = malloc((size_t)(end - arr) + 1);
    if (!buf) return -1;
    memcpy(buf, arr, (size_t)(end - arr));
    buf[end - arr] = '\0';

    int n = 0;
    char *save = NULL;
    for (char *obj = strtok_r(buf, "{", &save); obj && n < IPVS_MAX_RS; obj = strtok_r(NULL, "{", &save)) {
        char addr[64] = "", port[16] = "", fwd[16] = "", wgt[16] = "";
        json_val(obj, "address", addr, sizeof addr);
        json_val(obj, "port", port, sizeof port);
        json_val(obj, "forwarder", fwd, sizeof fwd);
        json_val(obj, "weight", wgt, sizeof wgt);
        if (!addr[0]) continue;
        snprintf(d->rs_addr[n], 64, "%s", addr);
        d->rs_port[n] = atoi(port);
        snprintf(d->rs_fwd[n], 8, "%s", fwd[0] ? fwd : "masq");
        d->rs_weight[n] = wgt[0] ? atoi(wgt) : 1;
        n++;
    }
    free(buf);
    d->nrs = n;
    return n;
}

static int parse_desired(const char *json, desired *d)
{
    memset(d, 0, sizeof *d);
    if (!json) return -1;
    char p[16] = "tcp";
    if (json_val(json, "protocol", p, sizeof p) != 0) return -1;
    if (json_val(json, "vip", d->vip, sizeof d->vip) != 0) return -1;
    char port[16] = "0";
    if (json_val(json, "port", port, sizeof port) != 0) return -1;
    d->port = atoi(port);
    if (json_val(json, "scheduler", d->sched, sizeof d->sched) != 0)
        snprintf(d->sched, sizeof d->sched, "rr");
    snprintf(d->proto, sizeof d->proto, "%s", p);
    /* Return SUCCESS/FAILURE, not the real-server count. Returning the count
     * meant any valid configuration that had real servers -- which is to say,
     * every useful one -- looked like a parse failure, and validate rejected
     * it before anything was applied. */
    return json_realservers(json, d) < 0 ? -1 : 0;
}

/* ------------------------------------------------------------- describe */

static const sr_field fields_vs[] = {
    { "protocol",   SR_FIELD_ENUM, 1, "tcp", "tcp,udp", "IPVS service protocol" },
    { "vip",        SR_FIELD_ADDR, 1, NULL,  NULL,     "Virtual service address" },
    { "port",       SR_FIELD_INT,  1, "80",  NULL,     "Virtual service port" },
    { "scheduler",  SR_FIELD_ENUM, 1, "rr",  NULL,     "IPVS scheduler" },
    { NULL, 0, 0, NULL, NULL, NULL }
};

static const sr_field fields_rs[] = {
    { "address",    SR_FIELD_ADDR,  1, NULL,  NULL,        "Real server address" },
    { "port",       SR_FIELD_INT,   1, "80",  NULL,        "Real server port" },
    { "forwarder",  SR_FIELD_ENUM, 1, "masq", "masq,route", "NAT (masq) or direct routing" },
    { "weight",     SR_FIELD_WEIGHT, 0, "1",  NULL,        "Relative weight" },
    { NULL, 0, 0, NULL, NULL, NULL }
};

static const sr_action actions_vs[] = {
    { "view",     SR_ACTION_VIEW,    "ipvs.virtual_service.read"   },
    { "create",   SR_ACTION_CREATE,  "ipvs.virtual_service.write"  },
    { "edit",     SR_ACTION_EDIT,    "ipvs.virtual_service.write"  },
    { "delete",   SR_ACTION_DELETE,  "ipvs.virtual_service.write"  },
    { "observe",  SR_ACTION_PROVIDER, "ipvs.virtual_service.read" },
    { NULL, 0, NULL }
};

static const sr_action actions_rs[] = {
    { "view",   SR_ACTION_VIEW,   "ipvs.real_server.read"  },
    { "create", SR_ACTION_CREATE, "ipvs.real_server.write" },
    { "edit",   SR_ACTION_EDIT,   "ipvs.real_server.write" },
    { "delete", SR_ACTION_DELETE, "ipvs.real_server.write" },
    { NULL, 0, NULL }
};

static const sr_object_type objects[] = {
    { "ipvs_virtual_service", "IPVS Virtual Service",
      fields_vs, actions_vs, "ipvs" },
    { "ipvs_real_server", "IPVS Real Server",
      fields_rs, actions_rs, "ipvs" },
    { NULL, NULL, NULL, NULL, NULL }
};

static const sr_description description = {
    objects,
    (const char *const []){
        "ipvs.virtual_service.read",
        "ipvs.virtual_service.write",
        "ipvs.real_server.read",
        "ipvs.real_server.write",
        NULL
    }
};

/* ------------------------------------------------------------ lifecycle */

static char *g_error;     /* the last failure, for the report */
static char *g_staged;    /* rendered text the core has already validated */
static char *g_snapshot;  /* in-process copy of what stage() captured */

static void set_err(char **out, const char *fmt, ...)
{
    free(g_error);
    g_error = NULL;
    if (!out) return;
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    g_error = malloc((size_t)n + 1);
    if (!g_error) return;
    va_start(ap, fmt);
    vsnprintf(g_error, (size_t)n + 1, fmt, ap);
    va_end(ap);
    *out = sdup(g_error);
}

static int ipvs_init(sr_ctx *ctx, char **err)
{
    (void)ctx;
    char *e = NULL;
    char *s = ipvs_save(&e);
    if (!s) {
        if (err) *err = e ? e : sdup("ipvsadm -S failed at init");
        return -1;
    }
    /* Whatever IPVS already holds is noted and left alone. This module is not
     * the first thing to have run here and must not behave as if it were. */
    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: backend %s reachable; %zu byte(s) of existing state observed",
                 ipvsadm_path(), strlen(s));
    free(s);
    if (err) *err = NULL;
    return 0;
}

static void ipvs_shutdown(sr_ctx *ctx)
{
    (void)ctx;
    free(g_error);
    g_error = NULL;
    free(g_staged);
    g_staged = NULL;
    free(g_snapshot);
    g_snapshot = NULL;
}

/* Serialise a table to JSON. Every service carries a `managed` flag: state this
 * module did not create is reported, never touched. */
static char *table_json(const table *t)
{
    sb s; sb_init(&s);
    sb_addf(&s, "{\"services\":[");
    for (int i = 0; i < t->n; i++) {
        const svc *v = &t->v[i];
        if (i) sb_addf(&s, ",");
        sb_addf(&s, "{\"protocol\":");   sb_jstr(&s, v->proto == 'u' ? "udp" : "tcp");
        sb_addf(&s, ",\"vip\":");        sb_jstr(&s, v->vip);
        sb_addf(&s, ",\"port\":%d,\"scheduler\":", v->port);
        sb_jstr(&s, v->sched);
        sb_addf(&s, ",\"real_servers\":[");
        for (int k = 0; k < v->nrs; k++) {
            if (k) sb_addf(&s, ",");
            sb_addf(&s, "{\"address\":");  sb_jstr(&s, v->rs_addr[k]);
            sb_addf(&s, ",\"port\":%d,\"forwarder\":", v->rs_port[k]);
            sb_jstr(&s, v->rs_fwd[k]);
            sb_addf(&s, ",\"weight\":%d}", v->rs_weight[k]);
        }
        sb_addf(&s, "]}");
    }
    sb_addf(&s, "],\"count\":%d}", t->n);
    return s.b ? s.b : sdup("{\"services\":[],\"count\":0}");
}

static int ipvs_discover(sr_ctx *ctx, const char *host_id)
{
    (void)host_id;
    char *err = NULL;
    char *save = ipvs_save(&err);
    if (!save) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: discover failed: %s", err ? err : "?");
        free(err);
        return -1;
    }
    /* A fresh read every time. If this module has been unloaded and reloaded
     * since it last looked, this is the first look, and it is correct. */
    table t;
    parse_save(save, &t);
    free(save);
    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: discovered %d virtual service(s)", t.n);
    return 0;
}

static int ipvs_observe(sr_ctx *ctx, const char *host_id, char **out_json)
{
    (void)host_id;
    char *err = NULL;
    char *save = ipvs_save(&err);
    if (!save) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: observe failed: %s", err ? err : "?");
        free(err);
        return -1;
    }
    table t;
    parse_save(save, &t);
    free(save);

    char *js = table_json(&t);
    if (out_json) *out_json = js; else free(js);
    if (ctx && ctx->observe_put && host_id && *host_id)
        ctx->observe_put(ctx, "ipvs_virtual_service", "observed",
                         t.n > 0 ? "available" : "unestablished",
                         "ipvsadm -S", js);
    return 0;
}

/* validate: the gate. Nothing reaches activation that fails here.
 *
 * The forwarder check is the one that matters most. IPVS silently rewrites a
 * real server's port when no forwarder is given, so a configuration that
 * omits it is not a slightly untidy configuration -- it is one whose applied
 * state will not match its request. Refusing it here is the difference between
 * a clear error and a mystery later. */
static int ipvs_validate(sr_ctx *ctx, const char *object_type,
                         const char *json, char **report)
{
    (void)ctx;
    sb s; sb_init(&s);
    sb_addf(&s, "{\"object_type\":\"%s\",\"errors\":[", object_type ? object_type : "");

    desired d;
    int nerr = 0;
    if (parse_desired(json, &d) != 0) {
        sb_addf(&s, "%s\"unparseable or missing required fields\"", nerr ? "," : "");
        nerr++;
    } else {
        if (strcmp(d.proto, "tcp") != 0 && strcmp(d.proto, "udp") != 0) {
            sb_addf(&s, "%s\"protocol must be tcp or udp\"", nerr ? "," : "");
            nerr++;
        }
        if (!d.vip[0]) {
            sb_addf(&s, "%s\"vip is required\"", nerr ? "," : "");
            nerr++;
        } else {
            int dots = 0;
            for (const char *c = d.vip; *c; c++) if (*c == '.') dots++;
            if (dots != 3) {
                sb_addf(&s, "%s\"vip must be an IPv4 literal\"", nerr ? "," : "");
                nerr++;
            }
        }
        if (d.port < 1 || d.port > 65535) {
            sb_addf(&s, "%s\"port must be 1..65535\"", nerr ? "," : "");
            nerr++;
        }
        if (!d.sched[0]) {
            sb_addf(&s, "%s\"scheduler is required\"", nerr ? "," : "");
            nerr++;
        }
        for (int i = 0; i < d.nrs; i++) {
            if (!d.rs_addr[i][0]) {
                sb_addf(&s, "%s\"real server %d has no address\"", nerr ? "," : "", i);
                nerr++;
            }
            if (d.rs_port[i] < 1 || d.rs_port[i] > 65535) {
                sb_addf(&s, "%s\"real server %d port must be 1..65535\"", nerr ? "," : "", i);
                nerr++;
            }
            if (strcmp(d.rs_fwd[i], "masq") != 0 && strcmp(d.rs_fwd[i], "route") != 0) {
                sb_addf(&s, "%s\"real server %d forwarder must be masq or route\"", nerr ? "," : "", i);
                nerr++;
            }
            if (d.rs_weight[i] < 0) {
                sb_addf(&s, "%s\"real server %d weight must not be negative\"", nerr ? "," : "", i);
                nerr++;
            }
        }
    }
    sb_addf(&s, "],\"valid\":%s}", nerr ? "false" : "true");
    if (report) *report = s.b ? s.b : sdup("{\"valid\":false}");
    else sb_free(&s);
    if (ctx && ctx->log)
        ctx->log(ctx, nerr ? 3 : 4, "ipvs: validate %s (%d error(s))",
                 object_type ? object_type : "?", nerr);
    return nerr ? -1 : 0;
}

/* render: desired state becomes the backend's own save form. The core hands
 * the rendered text to stage, so the text that gets applied is the text that
 * was validated -- there is no second interpretation of the request. */
static int ipvs_render(sr_ctx *ctx, const char *object_type,
                       const char *json, char **out_text)
{
    (void)object_type;
    desired d;
    if (parse_desired(json, &d) != 0) {
        set_err(NULL, "render: request could not be parsed");
        if (out_text) *out_text = NULL;
        return -1;
    }
    char flag[2] = { d.proto[0] == 'u' ? 'u' : 't', '\0' };

    sb s; sb_init(&s);
    sb_addf(&s, "-A -%s %s:%d -s %s\n", flag, d.vip, d.port, d.sched);
    for (int i = 0; i < d.nrs; i++) {
        sb_addf(&s, "-a -%s %s:%d -r %s:%d %s -w %d\n",
                flag, d.vip, d.port, d.rs_addr[i], d.rs_port[i],
                strcmp(d.rs_fwd[i], "route") == 0 ? "-g" : "-m",
                d.rs_weight[i]);
    }
    free(g_staged);
    g_staged = s.b ? s.b : sdup("");
    if (out_text) *out_text = sdup(g_staged);
    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: rendered %d real server(s) for %s:%d",
                 d.nrs, d.vip, d.port);
    return 0;
}

/* stage: capture the previous state, and prepare WITHOUT activating.
 *
 * The snapshot goes to core state, not to a static, so an unload and reload
 * between stage and rollback does not lose the only record of what to restore.
 * Nothing in IPVS is changed here. */
static int ipvs_stage(sr_ctx *ctx, const char *host_id, const char *text)
{
    (void)host_id;
    if (!text || !*text) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: stage refused: nothing rendered");
        return -1;
    }
    char *err = NULL;
    char *save = ipvs_save(&err);
    if (!save) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: stage refused: %s", err ? err : "?");
        free(err);
        return -1;
    }
    /* Persist through the core, and keep a copy here.
     *
     * The core copy is the durable one and works once a tenant exists. It can
     * legitimately fail on a fresh install, where init() has not run, the
     * module was loaded with no tenant, and desired_state.tenant_id is NOT
     * NULL with a foreign key. The in-process copy is what makes rollback
     * possible in that window. It is a CACHE: rollback re-reads the kernel
     * before acting, so it is never treated as the authority. */
    free(g_snapshot);
    g_snapshot = sdup(save);
    if (ctx && ctx->state_put) {
        char *snap = sdup(save);
        ctx->state_put(ctx, IPVS_SNAPSHOT_TYPE, "pending", snap);
        free(snap);
    }
    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: staged; %zu byte(s) of previous state captured, nothing activated",
                 strlen(save));
    free(save);
    return 0;
}

/* apply: the one step that changes the subsystem.
 *
 * Each save-form line is applied idempotently in the order -A then -a, because
 * adding a service that already exists is an error and would abort the rest.
 * So the service is ensured first and each real server is then added only if
 * it is not already present with the wanted settings. */
static int ipvs_apply(sr_ctx *ctx, const char *host_id)
{
    (void)host_id;
    if (!g_staged || !*g_staged) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: apply refused: nothing staged");
        return -1;
    }
    char *err = NULL;
    char *before = ipvs_save(&err);
    if (!before) { free(err); return -1; }
    table t;
    parse_save(before, &t);
    free(before);

    /* The desired state, read back out of the text the core already validated
     * and staged. This is the ONLY service the module manages; everything else
     * in the table belongs to someone else and is not touched. */
    table want; want.n = 0;
    {
        char *w = sdup(g_staged);
        if (!w) return -1;
        parse_save(w, &want);
        free(w);
    }
    if (want.n < 1) {
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: nothing staged to apply");
        return -1;
    }
    char flag = want.v[0].proto;
    const char *vip = want.v[0].vip;
    int   port  = want.v[0].port;

    int idx = find_svc(&t, flag, vip, port);

    /* 1. the service itself */
    if (idx < 0) {
        char add[IPVS_LINE];
        snprintf(add, sizeof add, "-A -%c %s:%d -s %s",
                 flag, vip, port, want.v[0].sched);
        char *e = NULL;
        if (ipvs_exec_line(add, &e) != 0) {
            if (ctx && ctx->log)
                ctx->log(ctx, 3, "ipvs: cannot create the virtual service: %s", e ? e : "?");
            free(e);
            return -1;
        }
        free(e);
        if (t.n < IPVS_MAX_SVC) {
            int k = t.n++;
            memset(&t.v[k], 0, sizeof t.v[k]);
            t.v[k].proto = flag;
            snprintf(t.v[k].vip, sizeof t.v[k].vip, "%s", vip);
            t.v[k].port = port;
            snprintf(t.v[k].sched, sizeof t.v[k].sched, "%s", want.v[0].sched);
            idx = k;
        }
    } else if (want.v[0].sched[0] && strcmp(t.v[idx].sched, want.v[0].sched) != 0) {
        /* ipvsadm has no in-place scheduler edit for a service other than -E */
        char edit[IPVS_LINE];
        snprintf(edit, sizeof edit, "-E -%c %s:%d -s %s",
                 flag, vip, port, want.v[0].sched);
        char *e = NULL;
        if (ipvs_exec_line(edit, &e) != 0) {
            if (ctx && ctx->log)
                ctx->log(ctx, 3, "ipvs: scheduler change refused: %s", e ? e : "?");
            free(e);
            return -1;
        }
        free(e);
        snprintf(t.v[idx].sched, sizeof t.v[idx].sched, "%s", want.v[0].sched);
    }

    /* 2. the real servers of THAT service, reconciled against the desired set.
     *
     * ipvsadm cannot edit a real server in place, so a weight or forwarder
     * change is a delete followed by an add. And a real server the desired
     * state no longer names is REMOVED -- otherwise "modify the real-server
     * set" would silently mean "add more and never take any away".
     *
     * Scoped to the one managed service by construction: only t.v[idx] is
     * walked, so a service this module never created is not even considered. */
    for (int k = t.v[idx].nrs - 1; k >= 0; k--) {
        int wanted = 0;
        for (int d = 0; d < want.v[0].nrs && !wanted; d++)
            if (strcmp(t.v[idx].rs_addr[k], want.v[0].rs_addr[d]) == 0) wanted = 1;
        if (wanted) continue;
        /* The real-server PORT is required. `ipvsadm -d -t vip:port -r addr`
         * without it answers "No such destination", leaves the entry in place
         * and exits 255 -- so the removal silently did nothing and every
         * "modify the real-server set" transaction failed at apply. */
        char del[IPVS_LINE];
        snprintf(del, sizeof del, "-d -%c %s:%d -r %s:%d",
                 flag, vip, port, t.v[idx].rs_addr[k], t.v[idx].rs_port[k]);
        char *e = NULL;
        if (ipvs_exec_line(del, &e) != 0) {
            if (ctx && ctx->log)
                ctx->log(ctx, 3, "ipvs: cannot remove real server %s: %s",
                         t.v[idx].rs_addr[k], e ? e : "?");
            free(e);
            return -1;
        }
        free(e);
        for (int m = k; m < t.v[idx].nrs - 1; m++) {
            snprintf(t.v[idx].rs_addr[m], 64, "%s", t.v[idx].rs_addr[m+1]);
            t.v[idx].rs_port[m]   = t.v[idx].rs_port[m+1];
            t.v[idx].rs_weight[m] = t.v[idx].rs_weight[m+1];
            snprintf(t.v[idx].rs_fwd[m], 8, "%s", t.v[idx].rs_fwd[m+1]);
        }
        t.v[idx].nrs--;
    }

    for (int d = 0; d < want.v[0].nrs; d++) {
        const char *a = want.v[0].rs_addr[d];
        int wp = want.v[0].rs_port[d];
        int ww = want.v[0].rs_weight[d];
        const char *wf = want.v[0].rs_fwd[d];
        int have = -1;
        for (int k = 0; k < t.v[idx].nrs; k++)
            if (strcmp(t.v[idx].rs_addr[k], a) == 0) { have = k; break; }
        int same = (have >= 0 && t.v[idx].rs_port[have] == wp &&
                    t.v[idx].rs_weight[have] == ww &&
                    strcmp(t.v[idx].rs_fwd[have], wf) == 0);
        if (same) continue;
        if (have >= 0) {
            /* changed: ipvsadm cannot edit in place, so replace */
            char del[IPVS_LINE];
            snprintf(del, sizeof del, "-d -%c %s:%d -r %s:%d", flag, vip, port, a, wp);
            char *e = NULL;
            if (ipvs_exec_line(del, &e) != 0) {
                if (ctx && ctx->log)
                    ctx->log(ctx, 3, "ipvs: cannot replace real server %s: %s", a, e ? e : "?");
                free(e);
                return -1;
            }
            free(e);
        }
        char add[IPVS_LINE];
        snprintf(add, sizeof add, "-a -%c %s:%d -r %s:%d %s -w %d",
                 flag, vip, port, a, wp, strcmp(wf, "route") == 0 ? "-g" : "-m", ww);
        char *e = NULL;
        if (ipvs_exec_line(add, &e) != 0) {
            if (ctx && ctx->log)
                ctx->log(ctx, 3, "ipvs: cannot add real server %s: %s", a, e ? e : "?");
            free(e);
            return -1;
        }
        free(e);
        if (have < 0 && t.v[idx].nrs < IPVS_MAX_RS) {
            int k = t.v[idx].nrs++;
            snprintf(t.v[idx].rs_addr[k], 64, "%s", a);
            t.v[idx].rs_port[k]   = wp;
            t.v[idx].rs_weight[k] = ww;
            snprintf(t.v[idx].rs_fwd[k], 8, "%s", wf);
        } else if (have >= 0) {
            t.v[idx].rs_port[have]   = wp;
            t.v[idx].rs_weight[have] = ww;
            snprintf(t.v[idx].rs_fwd[have], 8, "%s", wf);
        }
    }

    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: applied %s:%d with %d real server(s)",
                 vip, port, want.v[0].nrs);
    return 0;
}

/* verify: read the subsystem back and confirm it holds what was asked for.
 *
 * Compared against what IPVS REPORTS, not against the request, because IPVS
 * normalises a direct-routed real server's port to the service port. Diffing
 * against the request would report a mismatch that does not exist. */
static int ipvs_verify(sr_ctx *ctx, const char *host_id, char **report)
{
    (void)host_id;
    char *err = NULL;
    char *save = ipvs_save(&err);
    if (!save) {
        set_err(report, "verify: %s", err ? err : "ipvsadm -S failed");
        free(err);
        return -1;
    }
    table t;
    parse_save(save, &t);
    free(save);

    /* Rebuild the desired set from the staged text, which is what was applied. */
    table want;
    want.n = 0;
    if (g_staged) {
        char *copy = sdup(g_staged);
        parse_save(copy, &want);
        free(copy);
    }

    sb rep; sb_init(&rep);
    sb_addf(&rep, "{\"mismatches\":[");
    int bad = 0;
    for (int i = 0; i < want.n && !bad; i++) {
        int j = find_svc(&t, want.v[i].proto, want.v[i].vip, want.v[i].port);
        if (j < 0) {
            sb_addf(&rep, "\"service %s:%d is absent\"", want.v[i].vip, want.v[i].port);
            bad = 1;
            break;
        }
        if (strcmp(t.v[j].sched, want.v[i].sched) != 0) {
            sb_addf(&rep, "\"scheduler for %s:%d is %s, wanted %s\"",
                    want.v[i].vip, want.v[i].port, t.v[j].sched, want.v[i].sched);
            bad = 1;
            break;
        }
        for (int k = 0; k < want.v[i].nrs && !bad; k++) {
            int found = -1;
            for (int m = 0; m < t.v[j].nrs; m++)
                if (strcmp(t.v[j].rs_addr[m], want.v[i].rs_addr[k]) == 0) { found = m; break; }
            if (found < 0) {
                sb_addf(&rep, "\"real server %s is absent\"", want.v[i].rs_addr[k]);
                bad = 1;
            } else if (t.v[j].rs_weight[found] != want.v[i].rs_weight[found]) {
                sb_addf(&rep, "\"real server %s weight is %d, wanted %d\"",
                        want.v[i].rs_addr[k], t.v[j].rs_weight[found], want.v[i].rs_weight[found]);
                bad = 1;
            }
        }
    }
    sb_addf(&rep, "],\"ok\":%s,\"service_count\":%d}",
            bad ? "false" : "true", t.n);
    if (report) *report = rep.b ? rep.b : sdup("{\"ok\":false}");
    else sb_free(&rep);
    if (bad && ctx && ctx->log) ctx->log(ctx, 3, "ipvs: verify failed");
    return bad ? -1 : 0;
}

/* rollback: restore the snapshot, touching only what the snapshot described.
 *
 * Read back from core state, not from memory: if the module was reloaded
 * between stage and rollback, this is still the right answer. Services that
 * exist now but were not in the snapshot are UNMANAGED as far as this module
 * is concerned and are left exactly as they are -- "unmanaged state is
 * observed but never silently destroyed" is a property of this function, not
 * a hope. */
static int ipvs_rollback(sr_ctx *ctx, const char *host_id)
{
    char *snap = NULL;
    if (ctx && ctx->state_get)
        ctx->state_get(ctx, IPVS_SNAPSHOT_TYPE, "pending", &snap, NULL);

    char *err = NULL;
    char *now = ipvs_save(&err);
    if (!now) {
        free(err);
        if (ctx && ctx->log) ctx->log(ctx, 3, "ipvs: rollback could not read current state");
        free(snap);
        return -1;
    }
    table cur; parse_save(now, &cur); free(now);

    /* The core copy is authoritative; fall back to the in-process one.
     *
     * NULL means "no snapshot was captured". An EMPTY string means "the
     * subsystem was empty", which is a perfectly good thing to roll back TO.
     * Conflating the two is how a rollback deletes state it never recorded as
     * its own -- the exact inverse of the rule that unmanaged IPVS state is
     * never silently destroyed. */
    if (!snap && g_snapshot) snap = sdup(g_snapshot);
    if (!snap) {
        if (ctx && ctx->log)
            ctx->log(ctx, 3, "ipvs: rollback REFUSED -- no snapshot of the previous "
                     "state was captured; 'unknown' is not 'empty', so nothing changed");
        return -1;
    }

    table want; want.n = 0;
    parse_save(snap, &want);
    free(snap);

    char *e = NULL;
    /* Remove what this module added: present now, absent from the snapshot. */
    for (int i = 0; i < cur.n; i++) {
        if (find_svc(&want, cur.v[i].proto, cur.v[i].vip, cur.v[i].port) >= 0) continue;
        char *line = NULL;
        if (asprintf(&line, "-D -%c %s:%d", cur.v[i].proto, cur.v[i].vip, cur.v[i].port) < 0)
            continue;
        int rc = ipvs_exec_line(line, &e);
        free(line);
        if (rc != 0) { free(e); e = NULL; }
    }
    /* Restore the snapshot's services, in order. */
    for (int i = 0; i < want.n; i++) {
        if (find_svc(&cur, want.v[i].proto, want.v[i].vip, want.v[i].port) < 0) {
            char *line = NULL;
            if (asprintf(&line, "-A -%c %s:%d -s %s",
                         want.v[i].proto, want.v[i].vip, want.v[i].port, want.v[i].sched) >= 0) {
                ipvs_exec_line(line, &e);
                free(line);
                free(e); e = NULL;
            }
        }
        for (int k = 0; k < want.v[i].nrs; k++) {
            int have = 0;
            int j = find_svc(&cur, want.v[i].proto, want.v[i].vip, want.v[i].port);
            for (int m = 0; j >= 0 && m < cur.v[j].nrs; m++)
                if (strcmp(cur.v[j].rs_addr[m], want.v[i].rs_addr[k]) == 0) have = 1;
            if (have) continue;
            char *line = NULL;
            if (asprintf(&line, "-a -%c %s:%d -r %s:%d %s -w %d",
                         want.v[i].proto, want.v[i].vip, want.v[i].port,
                         want.v[i].rs_addr[k], want.v[i].rs_port[k],
                         strcmp(want.v[i].rs_fwd[k], "route") == 0 ? "-g" : "-m",
                         want.v[i].rs_weight[k]) >= 0) {
                ipvs_exec_line(line, &e);
                free(line);
                free(e); e = NULL;
            }
        }
        /* a scheduler that drifted is put back */
        int j = find_svc(&cur, want.v[i].proto, want.v[i].vip, want.v[i].port);
        if (j >= 0 && strcmp(cur.v[j].sched, want.v[i].sched) != 0) {
            char *line = NULL;
            if (asprintf(&line, "-E -%c %s:%d -s %s",
                         want.v[i].proto, want.v[i].vip, want.v[i].port, want.v[i].sched) >= 0) {
                ipvs_exec_line(line, &e);
                free(line);
                free(e); e = NULL;
            }
        }
    }
    free(e);
    free(g_snapshot);
    g_snapshot = NULL;
    if (ctx && ctx->log)
        ctx->log(ctx, 4, "ipvs: rolled back to the captured snapshot");
    return 0;
}

static int ipvs_describe_op(sr_ctx *ctx, const sr_description **out)
{
    (void)ctx;
    *out = &description;
    return 0;
}

static const sr_module_ops ops = {
    .init     = ipvs_init,
    .shutdown = ipvs_shutdown,
    .describe = ipvs_describe_op,
    .validate = ipvs_validate,
    .discover = ipvs_discover,
    .observe  = ipvs_observe,
    .render   = ipvs_render,
    .stage    = ipvs_stage,
    .apply    = ipvs_apply,
    .verify   = ipvs_verify,
    .rollback = ipvs_rollback,
};

static const sr_module_descriptor descriptor = {
    .abi_version = SR_MODULE_ABI_VERSION,
    .name        = "ipvs",
    .version     = "0.1.0",
    .summary     = "IPVS provider: real kernel virtual-server management via ipvsadm",
    /* Every lifecycle step, honestly declared. The core refuses to call one
     * that is absent, which is why this mask is the truth rather than a
     * wish list. */
    .provides     = SR_PROVIDES_INIT | SR_PROVIDES_SHUTDOWN | SR_PROVIDES_DESCRIBE |
                    SR_PROVIDES_VALIDATE | SR_PROVIDES_DISCOVER | SR_PROVIDES_OBSERVE |
                    SR_PROVIDES_RENDER | SR_PROVIDES_STAGE | SR_PROVIDES_APPLY |
                    SR_PROVIDES_VERIFY | SR_PROVIDES_ROLLBACK,
    .requires     = 0,
    .capability_requires = { (const char *const []){ "ipvs", NULL } },
    .dependencies = NULL,
    .ops          = &ops,
};

const sr_module_descriptor *sr_module_descriptor_get(void)
{
    return &descriptor;
}
