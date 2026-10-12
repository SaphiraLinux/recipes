/* module.c -- runtime module discovery, versioned ABI, refusal diagnostics.
 *
 * Discovery is RUNTIME, not a compiled-in list (D2 7). A module whose ABI
 * the core does not implement is refused with a clear diagnostic and never
 * loaded optimistically (D2 6). Loading is by absolute path: Saphira is
 * non-merged-/usr with a compiled-in musl path, so module location is
 * explicit and never an ld.so.conf/ldconfig mechanism (D1 9).
 *
 * The registry this builds is what the TUI derives its sections from, so
 * installing a module makes functionality APPEAR and removing it makes it
 * disappear cleanly, with no interface change (D2 8).
 */

#include "sr_module.h"
#include "sr_db.h"
#include "sr_rbac.h"
#include "sr.h"
#include "sr_audit.h"

#include <dirent.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Owns its identity strings. The previous form borrowed the caller's const
 * char*, and the caller frequently passed string literals or its own locals --
 * so a borrowed pointer could outlive its target just as easily as the struct
 * itself did. */
typedef struct {
    sr_db  *db;
    char   *actor_id;    /* owned */
    char   *tenant_id;   /* owned */
} mod_core;

static void mod_core_free(mod_core *c)
{
    if (!c) return;
    free(c->actor_id);
    free(c->tenant_id);
    c->actor_id = NULL;
    c->tenant_id = NULL;
}

typedef struct sr_loaded_module {
    void       *handle;
    const sr_module_descriptor *desc;
    sr_ctx      ctx;               /* services handed to the module */
    mod_core   *core;              /* owned, and what ctx->core points at */
    struct sr_loaded_module *next;
} sr_loaded_module;

static sr_loaded_module *g_modules;
static int g_count;

/* -------------------------------------------------- core services
 *
 * These are the ONLY routes a module has to authority, state, secrets,
 * audit and the registry. There is deliberately no sqlite3* in here: a
 * module cannot reach the database through the supported surface because it
 * is never given one (D2 5, D3 2).
 *
 * The core is the only writer; a module asking to change desired state
 * goes through here, where the actor's authorization is checked.
 */

/* Resolve the void * a module handed back into the core context that owns it.
 *
 * The ABI gives a module one sr_ctx, and every service takes `void *ctx`,
 * which the module passes back UNCHANGED. So what the core actually receives
 * is the sr_ctx it created -- not the mod_core sitting behind it. Casting the
 * incoming pointer straight to mod_core* read three fields out of the wrong
 * struct, and all three came back as CODE addresses, so the first service a
 * provider called died in libsqlite3 on a garbage sr_db*.
 *
 * That is not one broken function: authorize, state_get, state_put,
 * observe_put, audit, secret_ref and host_capability all did it. They went
 * unnoticed because the fixture modules call no core service at all, and the
 * loader's own internal calls happened not to read the fields.
 *
 * Resolution is a short walk of a list that holds a handful of entries, and a
 * pointer matching neither our sr_ctx nor our mod_core is REFUSED rather than
 * dereferenced -- checking is the entire point of this function. */
static mod_core *core_of(void *vctx)
{
    for (sr_loaded_module *m = g_modules; m; m = m->next) {
        if (vctx == (void *)&m->ctx) return m->core;
        if (vctx == (void *)m->core) return m->core;
    }
    return NULL;
}

static int m_authorize(void *vctx, const char *capability, const char **reason)
{
    mod_core *c = core_of(vctx);
    if (!c) { if (reason) *reason = "unknown core context"; return -1; }
    char *why = NULL;
    int ok = sr_rbac_authorize(c->db, c->actor_id, c->tenant_id, capability, &why);
    if (!ok && reason) *reason = why;
    else free(why);
    return ok;
}

static int m_state_get(void *vctx, const char *object_type, const char *object_id,
                       char **out_json, int *out_len)
{
    /* Resolve rather than cast: see core_of(). The module passes the
     * sr_ctx it was given, not the core struct behind it. */
    mod_core *c = core_of(vctx);
    if (!c) return -1;
    if (out_len) *out_len = 0;
    int rc = sr_state_get(c->db, c->tenant_id, object_type, object_id, out_json);
    if (out_len && *out_json) *out_len = (int)strlen(*out_json);
    return rc;
}

static int m_state_put(void *vctx, const char *object_type, const char *object_id,
                       const char *desired_json)
{
    mod_core *c = core_of(vctx);
    if (!c) return -1;
    char *err = NULL;
    int rc = sr_state_put(c->db, c->tenant_id, object_type, object_id,
                          desired_json, c->actor_id, &err);
    if (err) { sr_log(SR_LOG_ERROR, "module state_put: %s", err); free(err); }
    return rc;
}

static int m_observe_put(void *vctx, const char *object_type, const char *object_id,
                         const char *health, const char *source,
                         const char *observed_json)
{
    mod_core *c = core_of(vctx);
    if (!c) return -1;
    return sr_observed_put(c->db, c->tenant_id, object_type, object_id,
                           health, source, observed_json, NULL);
}

static int m_audit(void *vctx, const char *action, const char *object_type,
                   const char *object_id, const char *outcome)
{
    /* Resolve rather than cast: see core_of(). The module passes the
     * sr_ctx it was given, not the core struct behind it. */
    mod_core *c = core_of(vctx);
    if (!c) return -1;
    char id[SR_MAX_ID];
    sr_gen_id(id, sizeof id);
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(c->db,
        "INSERT INTO audit_event(id,tenant_id,actor_id,action,object_type,"
        "object_id,outcome,created_at) VALUES(?,?,?,?,?,?,?,datetime('now'));",
        &st, NULL) < 0) return -1;
    sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, c->tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, c->actor_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, action, -1, SQLITE_STATIC);
    if (object_type) sqlite3_bind_text(st, 5, object_type, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 5);
    if (object_id) sqlite3_bind_text(st, 6, object_id, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 6);
    sqlite3_bind_text(st, 7, outcome, -1, SQLITE_STATIC);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    return rc == SQLITE_DONE ? 0 : -1;
}

static int m_secret_ref(void *vctx, const char *kind, const char *name,
                        char **out_ref)
{
    /* A secret is a REFERENCE, never a value (D3 5). For slice 1 there is no
     * secret store yet, so this records the reference shape and refuses to
     * invent a value. */
    (void)vctx;
    if (out_ref) *out_ref = NULL;
    if (!kind || !name) return -1;
    sr_log(SR_LOG_DEBUG, "secret_ref requested: kind=%s name=%s (reference only)",
           kind, name);
    return -1; /* no store in slice 1; never fabricate a secret */
}

static int m_register_description(void *vctx, const sr_description *desc)
{
    (void)vctx;
    /* The core owns the registry the TUI reads. Registration is recorded by
     * the loader during describe(); this entry point exists so a module can
     * contribute dynamically later without an ABI change. */
    if (!desc) return -1;
    return 0;
}

static int m_host_capability(void *vctx, const char *host_id,
                             const char *capability, char *out_state)
{
    /* Resolve rather than cast: see core_of(). The module passes the
     * sr_ctx it was given, not the core struct behind it. */
    mod_core *c = core_of(vctx);
    if (!c) return -1;
    char q[512];
    snprintf(q, sizeof q,
        "SELECT state FROM host_capability WHERE host_id='%s' AND capability='%s';",
        host_id, capability);
    char *st = NULL;
    if (sr_db_query_text(c->db, q, &st) < 0 || !st) {
        if (out_state) out_state[0] = '\0';
        free(st);
        return -1;
    }
    snprintf(out_state, 32, "%s", st);
    free(st);
    return 0;
}

static void m_log(void *vctx, int level, const char *fmt, ...)
{
    (void)vctx;
    va_list ap;
    char buf[SR_MAX_TEXT];
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    sr_log(level, "module: %s", buf);
}

static void fill_ctx(sr_ctx *ctx, mod_core *core)
{
    memset(ctx, 0, sizeof *ctx);
    ctx->authorize            = m_authorize;
    ctx->state_get            = m_state_get;
    ctx->state_put            = m_state_put;
    ctx->observe_put          = m_observe_put;
    ctx->audit                = m_audit;
    ctx->secret_ref           = m_secret_ref;
    ctx->register_description = m_register_description;
    ctx->host_capability      = m_host_capability;
    ctx->log                  = m_log;
    ctx->core                 = core;
}

const char *sr_capability_state_name(sr_capability_state s)
{
    switch (s) {
    case SR_CAP_UNAVAILABLE: return "unavailable";
    case SR_CAP_INSTALLED:   return "installed";
    case SR_CAP_AVAILABLE:   return "available";
    case SR_CAP_USABLE:      return "usable";
    case SR_CAP_HEALTHY:     return "healthy";
    case SR_CAP_UNESTABLISHED:
    default:                 return "unestablished";
    }
}

/* ------------------------------------------------------- registry rows */

/* Every registry decision is audited, refusals included: an operator has to
 * be able to see that a module was present and REFUSED, not merely absent. */
static void audit_module(sr_db *db, const char *name, const char *version,
                         const char *state, const char *diagnostic)
{
    char detail[256];
    snprintf(detail, sizeof detail, "%s%s%s", state,
             diagnostic && *diagnostic ? ": " : "", diagnostic ? diagnostic : "");
    /* The 9th and 10th sr_audit parameters are adjacent const char *, so a
     * swapped pair compiles silently. This one WAS swapped: the reason landed
     * in source_addr and detail came out NULL, which is how a refused module
     * ended up in the audit trail with no explanation on it at all. */
    sr_audit(db, NULL, NULL, NULL,
             strcmp(state, "loaded") == 0 ? "module.load" : "module.refuse",
             "module", name,
             strcmp(state, "loaded") == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_DENIED,
             NULL, detail);
}

static void record_registry(sr_db *db, const char *name, const char *version,
                            uint32_t abi, uint64_t provides, uint64_t requires,
                            const char *state, const char *diagnostic)
{
    char *err = NULL;
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO module_registry(module_name,module_version,abi_version,"
        "provides_mask,requires_mask,state,diagnostic,last_seen_at) "
        "VALUES(?,?,?,?,?,?,?,datetime('now')) "
        "ON CONFLICT(module_name,module_version) DO UPDATE SET "
        "state=excluded.state, diagnostic=excluded.diagnostic,"
        "last_seen_at=excluded.last_seen_at;", &st, &err) < 0) {
        free(err);
        return;
    }
    sqlite3_bind_text(st, 1, name, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, version, -1, SQLITE_STATIC);
    sqlite3_bind_int64(st, 3, abi);
    sqlite3_bind_int64(st, 4, (sqlite3_int64)provides);
    sqlite3_bind_int64(st, 5, (sqlite3_int64)requires);
    sqlite3_bind_text(st, 6, state, -1, SQLITE_STATIC);
    if (diagnostic) sqlite3_bind_text(st, 7, diagnostic, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 7);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

/* Drop rows that no module claimed during this pass. */
static void prune_stale(sr_db *db)
{
    sqlite3_stmt *m = NULL;
    if (sr_db_prepare(db, "DELETE FROM module_registry WHERE state='stale';",
                      &m, NULL) == 0) {
        sqlite3_step(m);
        sqlite3_finalize(m);
    }
}

/* ---------------------------------------------------------- loading */

/* Returns the number of modules successfully loaded BY THIS CALL. An absent
 * directory is not an error: the core is usable with no modules at all
 * (D2 7), so it returns 0 rather than failing. */
int sr_module_load_all(sr_db *db, const char *moddir, const char *actor_id,
                       const char *tenant_id)
{
    int loaded_here = 0;

    /* RECONCILE the registry against what is actually present. Without this
     * the table only ever accumulates, and a module that has been UNINSTALLED
     * keeps its 'loaded' row forever -- so the TUI would go on offering a
     * section for a module that no longer exists (D2 8). Every pass marks
     * prior rows stale, and whatever is still stale at the end is dropped. */
    {
        sqlite3_stmt *m = NULL;
        if (sr_db_prepare(db,
                "UPDATE module_registry SET state='stale', "
                "last_seen_at=datetime('now');", &m, NULL) == 0) {
            sqlite3_step(m);
            sqlite3_finalize(m);
        }
    }

    DIR *d = opendir(moddir);
    if (!d) {
        sr_log(SR_LOG_WARN,
               "module directory %s not present; core usable with no modules",
               moddir);
        prune_stale(db);
        return 0;
    }

    /* The template is only a TEMPLATE.
     *
     * It used to BE the ctx->core, which is how every loaded module ended up
     * holding the address of a stack local in this function. The pointer
     * stayed valid for the rest of the loop -- so loading looked fine -- and
     * dangled the moment load_all returned. Nothing noticed for a long time
     * because the fixture modules call no core service at all: the first
     * provider to use state_put dereferenced freed stack, got a garbage
     * sr_db*, and the daemon took a general protection fault inside
     * libsqlite3 -- presenting as "cannot reach the daemon".
     *
     * Each module now gets its own heap mod_core, whose lifetime is the
     * module's, and the identity strings are copied rather than borrowed. */
    mod_core tmpl = { .db = db, .actor_id = NULL, .tenant_id = NULL };
    sr_ctx ctx_template;
    fill_ctx(&ctx_template, &tmpl);

    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        size_t n = strlen(de->d_name);
        if (n < 4 || strcmp(de->d_name + n - 3, ".so") != 0) continue;

        char path[SR_MAX_PATH];
        snprintf(path, sizeof path, "%s/%s", moddir, de->d_name);

        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            sr_log(SR_LOG_ERROR, "%s: dlopen failed: %s", de->d_name, dlerror());
            continue;
        }

        /* A module whose ABI is not implemented is refused with a clear
         * diagnostic, never loaded optimistically (D2 6). */
        sr_module_descriptor_get_fn get =
            (sr_module_descriptor_get_fn)(uintptr_t)dlsym(h, "sr_module_descriptor_get");
        if (!get) {
            sr_log(SR_LOG_ERROR,
                   "%s: REFUSED -- does not export sr_module_descriptor_get",
                   de->d_name);
            record_registry(db, de->d_name, "?", 0, 0, 0, "refused",
                            "missing sr_module_descriptor_get");
            audit_module(db, de->d_name, "?", "refused",
                         "missing sr_module_descriptor_get");
            dlclose(h);
            continue;
        }

        const sr_module_descriptor *desc = get();
        if (!desc) {
            sr_log(SR_LOG_ERROR, "%s: REFUSED -- descriptor is NULL", de->d_name);
            record_registry(db, de->d_name, "?", 0, 0, 0, "refused", "NULL descriptor");
            dlclose(h);
            continue;
        }

        if (desc->abi_version != SR_MODULE_ABI_VERSION) {
            char diag[256];
            snprintf(diag, sizeof diag,
                     "module ABI %u is not supported; core implements ABI %d",
                     desc->abi_version, SR_MODULE_ABI_VERSION);
            sr_log(SR_LOG_ERROR, "%s: INCOMPATIBLE -- %s", desc->name, diag);
            record_registry(db, desc->name, desc->version ? desc->version : "?",
                            desc->abi_version, desc->provides, desc->requires,
                            "incompatible", diag);
            audit_module(db, desc->name, desc->version, "incompatible", diag);
            dlclose(h);
            continue;
        }

        if (desc->name == NULL || desc->ops == NULL) {
            sr_log(SR_LOG_ERROR, "%s: REFUSED -- descriptor missing name or ops",
                   de->d_name);
            record_registry(db, de->d_name, "?", desc->abi_version, 0, 0,
                            "refused", "descriptor missing name or ops");
            dlclose(h);
            continue;
        }

        sr_loaded_module *m = calloc(1, sizeof *m);
        if (!m) { dlclose(h); continue; }
        m->handle = h;
        m->desc = desc;
        m->core = calloc(1, sizeof *m->core);
        if (!m->core) { dlclose(m->handle); free(m); continue; }
        /* Copied, not borrowed: the caller may pass its own locals, and a
         * stored pointer must never depend on that caller outliving us. */
        m->core->db       = db;
        m->core->actor_id  = actor_id  ? strdup(actor_id)  : NULL;
        m->core->tenant_id = tenant_id ? strdup(tenant_id) : NULL;
        m->ctx = ctx_template;
        /* ...and ctx.core points at THIS module's own context, which lives
         * as long as it does. */
        m->ctx.core = m->core;

        if ((desc->provides & SR_PROVIDES_INIT) && desc->ops->init) {
            char *err = NULL;
            if (desc->ops->init(&m->ctx, &err) < 0) {
                sr_log(SR_LOG_ERROR, "%s: init failed: %s", desc->name,
                       err ? err : "?");
                record_registry(db, desc->name, desc->version, desc->abi_version,
                                desc->provides, desc->requires, "refused",
                                err ? err : "init failed");
                free(err);
                free(m);
                dlclose(h);
                continue;
            }
            free(err);
        }

        /* describe() is the declarative layer the TUI renders. Pull it now so
         * the registry is complete before any client connects. */
        if ((desc->provides & SR_PROVIDES_DESCRIBE) && desc->ops->describe) {
            const sr_description *sd = NULL;
            if (desc->ops->describe(&m->ctx, &sd) == 0 && sd) {
                m->ctx.register_description(&m->ctx, sd);
                int nobj = 0;
                for (int i = 0; sd->objects && sd->objects[i].type; i++) nobj++;
                sr_log(SR_LOG_INFO, "module %s %s: %d object type(s) described",
                       desc->name, desc->version, nobj);
            }
        }

        m->next = g_modules;
        g_modules = m;
        g_count++;
        loaded_here++;

        record_registry(db, desc->name, desc->version ? desc->version : "?",
                        desc->abi_version, desc->provides, desc->requires,
                        "loaded", NULL);
        audit_module(db, desc->name, desc->version, "loaded", NULL);
        sr_log(SR_LOG_INFO, "loaded module %s %s (abi %u, provides 0x%llx)",
               desc->name, desc->version, desc->abi_version,
               (unsigned long long)desc->provides);
    }
    closedir(d);
    prune_stale(db);
    return loaded_here;
}

int sr_module_count(void) { return g_count; }

/* Release the loaded modules and the context each one owns.
 *
 * Exists so the per-module mod_core is actually freed by whoever allocated it.
 * A provider that has been unloaded must not be able to reach a freed core
 * through a stale ctx, and a reload must start from nothing -- which is the
 * whole point of the rediscovery requirement: a module that trusts its own
 * previous memory after a reload is asserting something it never observed. */
void sr_module_unload_all(void)
{
    sr_loaded_module *m = g_modules;
    g_modules = NULL;
    g_count = 0;
    while (m) {
        sr_loaded_module *next = m->next;
        if (m->desc && (m->desc->provides & SR_PROVIDES_SHUTDOWN) &&
            m->desc->ops && m->desc->ops->shutdown)
            m->desc->ops->shutdown(&m->ctx);
        if (m->handle) dlclose(m->handle);
        mod_core_free(m->core);
        free(m->core);
        free(m);
        m = next;
    }
}

/* ------------------------------------------------------- provider access
 *
 * The core needs to reach a loaded module's operations without knowing what
 * any particular module does. These accessors hand back the ops table and the
 * service context by NAME, so the dispatch layer above can be written once,
 * generically, and no IPVS-specific (or ldirectord, or OVS) knowledge ever
 * enters the core.
 *
 * Returns NULL for an unknown or unloaded module; the caller must treat that
 * as a refusal, never as an empty operation set.
 */
const sr_module_ops *sr_module_ops_get(const char *name)
{
    for (sr_loaded_module *m = g_modules; m; m = m->next)
        if (m->desc && strcmp(m->desc->name, name) == 0)
            return m->desc->ops;
    return NULL;
}

sr_ctx *sr_module_ctx_get(const char *name)
{
    for (sr_loaded_module *m = g_modules; m; m = m->next)
        if (m->desc && strcmp(m->desc->name, name) == 0)
            return &m->ctx;
    return NULL;
}

uint64_t sr_module_provides_get(const char *name)
{
    for (sr_loaded_module *m = g_modules; m; m = m->next)
        if (m->desc && strcmp(m->desc->name, name) == 0)
            return m->desc->provides;
    return 0;
}

/* JSON view of the registry, for the CLI and the TUI. This is the ONLY
 * source of what functionality exists -- interfaces never hard-code it. */
char *sr_module_registry_json(sr_db *db)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT module_name,module_version,abi_version,provides_mask,"
        "state,COALESCE(diagnostic,'') FROM module_registry "
        "ORDER BY module_name,module_version;", &st, NULL) < 0)
        return sr_xstrdup("[]");

    size_t cap = 1024, len = 0;
    char *out = malloc(cap);
    len += (size_t)snprintf(out + len, cap - len, "[");
    int first = 1;
    while (sqlite3_step(st) == SQLITE_ROW) {
        const char *name = (const char *)sqlite3_column_text(st, 0);
        const char *ver  = (const char *)sqlite3_column_text(st, 1);
        const char *state = (const char *)sqlite3_column_text(st, 4);
        const char *diag  = (const char *)sqlite3_column_text(st, 5);
        int abi = sqlite3_column_int(st, 2);
        long long prov = sqlite3_column_int64(st, 3);

        if (len + 256 > cap) {
            cap *= 2;
            out = realloc(out, cap);
        }
        len += (size_t)snprintf(out + len, cap - len,
            "%s{\"name\":\"%s\",\"version\":\"%s\",\"abi_version\":%d,"
            "\"provides_mask\":%lld,\"state\":\"%s\",\"diagnostic\":\"%s\"}",
            first ? "" : ",", name, ver, abi, prov, state, diag);
        first = 0;
    }
    sqlite3_finalize(st);
    if (len + 4 > cap) { cap += 4; out = realloc(out, cap); }
    snprintf(out + len, cap - len, "]");
    return out;
}
