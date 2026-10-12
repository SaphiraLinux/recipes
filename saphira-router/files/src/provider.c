/* provider.c -- the core side of the module lifecycle.
 *
 * Two jobs, and deliberately nothing else:
 *
 *   1. sr_provider_invoke      -- dispatch ONE lifecycle step to a module,
 *                                 generically, enforcing the provides mask
 *                                 and auditing the outcome.
 *   2. sr_provider_transaction -- sequence the whole lifecycle for one
 *                                 desired-state change, and own the
 *                                 transaction around it.
 *
 * There is no subsystem knowledge in this file. It does not know what IPVS
 * is. If it grew that knowledge it would stop being a core and become a
 * second copy of the first provider, and the next provider would be written
 * against the IPVS path rather than against the ABI.
 */
#include "sr_provider.h"
#include "sr_module.h"
#include "sr_audit.h"
#include "sr.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------- step mapping */

const char *sr_step_name(sr_step step)
{
    switch (step) {
    case SR_STEP_INIT:     return "init";
    case SR_STEP_DISCOVER: return "discover";
    case SR_STEP_OBSERVE:  return "observe";
    case SR_STEP_VALIDATE: return "validate";
    case SR_STEP_RENDER:   return "render";
    case SR_STEP_STAGE:    return "stage";
    case SR_STEP_APPLY:    return "apply";
    case SR_STEP_VERIFY:   return "verify";
    case SR_STEP_ROLLBACK: return "rollback";
    case SR_STEP_SHUTDOWN: return "shutdown";
    }
    return "unknown";
}

uint64_t sr_step_provides_bit(sr_step step)
{
    switch (step) {
    case SR_STEP_INIT:     return SR_PROVIDES_INIT;
    case SR_STEP_DISCOVER: return SR_PROVIDES_DISCOVER;
    case SR_STEP_OBSERVE:  return SR_PROVIDES_OBSERVE;
    case SR_STEP_VALIDATE: return SR_PROVIDES_VALIDATE;
    case SR_STEP_RENDER:   return SR_PROVIDES_RENDER;
    case SR_STEP_STAGE:    return SR_PROVIDES_STAGE;
    case SR_STEP_APPLY:    return SR_PROVIDES_APPLY;
    case SR_STEP_VERIFY:   return SR_PROVIDES_VERIFY;
    case SR_STEP_ROLLBACK: return SR_PROVIDES_ROLLBACK;
    case SR_STEP_SHUTDOWN: return SR_PROVIDES_SHUTDOWN;
    }
    return 0;
}

/* The member of sr_module_ops that implements each step. Kept as a switch
 * rather than a table of member offsets so the compiler checks it against the
 * struct: adding a step to the enum without wiring it here fails to build
 * rather than dispatching to a NULL at runtime. */
static int call_step(sr_step step, const sr_module_ops *ops, sr_ctx *ctx,
                     const char *host_id, const char *object_type,
                     const char *json, char **out_text)
{
    char *err = NULL;
    if (out_text) *out_text = NULL;

    switch (step) {
    case SR_STEP_INIT:
        return ops->init(ctx, &err);
    case SR_STEP_DISCOVER:
        return ops->discover(ctx, host_id);
    case SR_STEP_OBSERVE: {
        char *j = NULL;
        int rc = ops->observe(ctx, host_id, &j);
        if (out_text) *out_text = j; else free(j);
        return rc;
    }
    case SR_STEP_VALIDATE: {
        char *rep = NULL;
        int rc = ops->validate(ctx, object_type, json, &rep);
        /* A validation report is useful even when validation FAILED: it says
         * why. So it is handed back either way, unlike a bare error. */
        if (out_text) *out_text = rep; else free(rep);
        return rc;
    }
    case SR_STEP_RENDER: {
        char *t = NULL;
        int rc = ops->render(ctx, object_type, json, &t);
        if (out_text) *out_text = t; else free(t);
        return rc;
    }
    case SR_STEP_STAGE:
        return ops->stage(ctx, host_id, json);
    case SR_STEP_APPLY:
        return ops->apply(ctx, host_id);
    case SR_STEP_VERIFY: {
        char *rep = NULL;
        int rc = ops->verify(ctx, host_id, &rep);
        if (out_text) *out_text = rep; else free(rep);
        return rc;
    }
    case SR_STEP_ROLLBACK:
        return ops->rollback(ctx, host_id);
    case SR_STEP_SHUTDOWN:
        ops->shutdown(ctx);
        return 0;
    }
    free(err);
    return -1;
}

int sr_step_invoke(sr_step step, const sr_module_ops *ops, sr_ctx *ctx,
                   const char *host_id, const char *object_type,
                   const char *json, char **out_text)
{
    if (!ops) return -1;
    return call_step(step, ops, ctx, host_id, object_type, json, out_text);
}

int sr_step_from_name(const char *name, sr_step *out)
{
    static const struct { const char *n; sr_step s; } map[] = {
        { "init", SR_STEP_INIT }, { "discover", SR_STEP_DISCOVER },
        { "observe", SR_STEP_OBSERVE }, { "validate", SR_STEP_VALIDATE },
        { "render", SR_STEP_RENDER }, { "stage", SR_STEP_STAGE },
        { "apply", SR_STEP_APPLY }, { "verify", SR_STEP_VERIFY },
        { "rollback", SR_STEP_ROLLBACK }, { "shutdown", SR_STEP_SHUTDOWN },
    };
    if (!name) return -1;
    for (size_t i = 0; i < sizeof map / sizeof *map; i++)
        if (strcmp(name, map[i].n) == 0) { if (out) *out = map[i].s; return 0; }
    return -1;
}

/* -------------------------------------------------------------- audit */

static void audit_step(sr_db *db, const char *module, sr_step step,
                       const char *tenant, const char *actor,
                       const char *host_id, const char *object_type,
                       const char *outcome, const char *detail)
{
    char action[96];
    snprintf(action, sizeof action, "provider.%s.%s", module, sr_step_name(step));
    sr_audit(db, tenant, actor, NULL, action, "provider", module,
             outcome, NULL, detail);
}

/* ------------------------------------------------------------ dispatch */

int sr_provider_invoke(sr_db *db, const char *module_name, sr_step step,
                       const char *actor_id, const char *tenant_id,
                       const char *host_id, const char *object_type,
                       const char *json, char **out_text, char **out_err)
{
    if (out_text) *out_text = NULL;
    if (out_err) *out_err = NULL;
    if (!module_name || !*module_name) return SR_ERR_FAILED;

    const sr_module_ops *ops = sr_module_ops_get(module_name);
    if (!ops) {
        char why[160];
        snprintf(why, sizeof why,
                 "module '%s' is not loaded", module_name);
        audit_step(db, module_name, step, tenant_id, actor_id, host_id,
                   object_type, SR_AUDIT_FAILED, why);
        if (out_err) *out_err = strdup(why);
        return SR_ERR_UNAVAILABLE;
    }

    /* A module that does not advertise a step must never be called for it.
     * Checking the mask here -- in the core, once -- is what makes the mask
     * binding rather than decorative. */
    uint64_t provides = sr_module_provides_get(module_name);
    uint64_t bit = sr_step_provides_bit(step);
    if (!bit || !(provides & bit)) {
        char detail[160];
        snprintf(detail, sizeof detail,
                 "module does not provide %s (provides mask 0x%llx)",
                 sr_step_name(step), (unsigned long long)provides);
        audit_step(db, module_name, step, tenant_id, actor_id, host_id,
                   object_type, SR_AUDIT_DENIED, detail);
        if (out_err) *out_err = strdup(detail);
        return SR_ERR_UNAVAILABLE;
    }

    sr_ctx *ctx = sr_module_ctx_get(module_name);
    char *out = NULL;
    int rc = call_step(step, ops, ctx, host_id, object_type, json, &out);
    audit_step(db, module_name, step, tenant_id, actor_id, host_id,
               object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED,
               out && *out ? out : NULL);
    if (out_text) *out_text = out; else free(out);
    return rc;
}

/* --------------------------------------------------------- transaction */

static void json_step(sr_db *db, char **buf, size_t *len, size_t *cap,
                      const char *name, int rc, const char *detail)
{
    size_t need = strlen(detail ? detail : "") + strlen(name) + 96;
    if (*len + need + 4 > *cap) {
        size_t nc = (*cap ? *cap : 1024);
        while (nc < *len + need + 4) nc *= 2;
        *buf = realloc(*buf, nc);
        *cap = nc;
    }
    *len += (size_t)snprintf(*buf + *len, *cap - *len, "%s\"%s\":{\"ok\":%s,\"detail\":\"%s\"}",
                            *len ? "," : "", name,
                            rc == 0 ? "true" : "false",
                            detail ? detail : "");
}

/* Undo, and say so. A rollback that itself fails is reported as its own step:
 * the outcome is then "apply failed AND rollback failed", which is a different
 * operational situation from "apply failed and was undone", and flattening the
 * two would be exactly the kind of dishonest outcome this project refuses. */
static void rollback(sr_db *db, const char *module_name, sr_ctx *ctx,
                     const char *tenant, const char *actor, const char *host_id,
                     const char *object_type, char **buf, size_t *len, size_t *cap)
{
    const sr_module_ops *ops = sr_module_ops_get(module_name);
    int rc = ops && ops->rollback ? ops->rollback(ctx, host_id) : -1;
    json_step(db, buf, len, cap, "rollback", rc,
              rc == 0 ? "previous state restored" : "ROLLBACK FAILED");
    audit_step(db, module_name, SR_STEP_ROLLBACK, tenant, actor, host_id,
               object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL);
}

int sr_provider_transaction(sr_db *db, const char *module_name,
                            const char *actor_id, const char *tenant_id,
                            const char *host_id, const char *object_type,
                            const char *desired_json, char **out_report)
{
    if (out_report) *out_report = NULL;
    if (!module_name || !desired_json) return SR_ERR_FAILED;

    const sr_module_ops *ops = sr_module_ops_get(module_name);
    if (!ops) {
        audit_step(db, module_name, SR_STEP_APPLY, tenant_id, actor_id,
                   host_id, object_type, SR_AUDIT_FAILED, "module is not loaded");
        return SR_ERR_UNAVAILABLE;
    }

    sr_ctx *ctx = sr_module_ctx_get(module_name);
    uint64_t provides = sr_module_provides_get(module_name);

    /* Every step the transaction depends on must be advertised. Refusing up
     * front means a partial provider cannot be driven halfway and left. */
    static const sr_step needed[] = {
        SR_STEP_DISCOVER, SR_STEP_VALIDATE, SR_STEP_RENDER,
        SR_STEP_STAGE, SR_STEP_APPLY, SR_STEP_VERIFY, SR_STEP_ROLLBACK
    };
    for (size_t i = 0; i < sizeof needed / sizeof *needed; i++) {
        if (!(provides & sr_step_provides_bit(needed[i]))) {
            char detail[160];
            snprintf(detail, sizeof detail,
                     "module %s does not provide %s, so a transaction cannot run",
                     module_name, sr_step_name(needed[i]));
            audit_step(db, module_name, needed[i], tenant_id, actor_id,
                       host_id, object_type, SR_AUDIT_DENIED, detail);
            return SR_ERR_UNAVAILABLE;
        }
    }

    char *rendered = NULL, *report_txt = NULL, *discovered = NULL;
    char *buf = NULL; size_t len = 0, cap = 0;
    int rc = SR_OK, applied = 0;

    /* discover: what the subsystem IS, before anything is decided. The
     * snapshot this produces is what rollback is measured against. */
    rc = ops->discover(ctx, host_id);
    json_step(db, &buf, &len, &cap, "discover", rc, rc == 0 ? "subsystem state captured" : "discover failed");
    audit_step(db, module_name, SR_STEP_DISCOVER, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL);
    if (rc != 0) goto done;

    /* validate: a bad configuration is refused HERE, before render, before
     * stage, and therefore before anything can be activated. */
    rc = ops->validate(ctx, object_type, desired_json, &report_txt);
    json_step(db, &buf, &len, &cap, "validate", rc,
              rc == 0 ? "configuration is valid" : (report_txt ? report_txt : "validation failed"));
    audit_step(db, module_name, SR_STEP_VALIDATE, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_DENIED,
               report_txt);
    if (rc != 0) { rc = SR_ERR_FAILED; goto done; }   /* nothing was touched */
    free(report_txt); report_txt = NULL;

    /* render: desired state becomes the module's own text form. */
    rc = ops->render(ctx, object_type, desired_json, &rendered);
    json_step(db, &buf, &len, &cap, "render", rc,
              rc == 0 ? "desired state rendered" : "render failed");
    audit_step(db, module_name, SR_STEP_RENDER, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL);
    if (rc != 0) { rc = SR_ERR_FAILED; goto done; }

    /* stage: prepared, NOT activated. */
    rc = ops->stage(ctx, host_id, rendered);
    json_step(db, &buf, &len, &cap, "stage", rc,
              rc == 0 ? "staged without activating" : "stage failed");
    audit_step(db, module_name, SR_STEP_STAGE, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL);
    if (rc != 0) { rc = SR_ERR_FAILED; goto done; }

    /* apply: the one step allowed to change the subsystem. */
    rc = ops->apply(ctx, host_id);
    applied = (rc == 0);
    json_step(db, &buf, &len, &cap, "apply", rc,
              rc == 0 ? "applied" : "apply failed; rolling back");
    audit_step(db, module_name, SR_STEP_APPLY, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL);
    if (rc != 0) { rollback(db, module_name, ctx, tenant_id, actor_id, host_id,
                            object_type, &buf, &len, &cap); rc = SR_ERR_FAILED; goto done; }

    /* verify: read the subsystem back and confirm it matches. A failed verify
     * is a real failure, and it rolls back -- it is not a warning. */
    rc = ops->verify(ctx, host_id, &report_txt);
    json_step(db, &buf, &len, &cap, "verify", rc,
              rc == 0 ? "verified against the subsystem" : (report_txt ? report_txt : "verification failed"));
    audit_step(db, module_name, SR_STEP_VERIFY, tenant_id, actor_id,
               host_id, object_type, rc == 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED,
               report_txt);
    if (rc != 0) {
        rollback(db, module_name, ctx, tenant_id, actor_id, host_id,
                 object_type, &buf, &len, &cap);
        rc = SR_ERR_FAILED;
        goto done;
    }

    /* observe after a successful apply, so the observed record reflects what
     * the subsystem actually holds rather than what was asked for. */
    if (provides & SR_PROVIDES_OBSERVE) {
        ops->observe(ctx, host_id, &discovered);
        json_step(db, &buf, &len, &cap, "observe", 0, "observed state recorded");
    }
    rc = SR_OK;

done:
    if (out_report) {
        if (buf) {
            size_t n = len + 3;
            char *r = malloc(n);
            snprintf(r, n, "{%s}%s", buf, applied && rc == 0 ? "" : "");
            *out_report = r;
        } else {
            *out_report = strdup("{}");
        }
    } else {
        free(buf);
    }
    free(rendered);
    free(report_txt);
    free(discovered);
    return rc;
}
