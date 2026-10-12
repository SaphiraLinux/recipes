/* sr_provider.h -- generic provider dispatch and transaction orchestration.
 *
 * The module ABI (sr_module.h) already declares the whole provider
 * lifecycle: init, discover, observe, validate, render, stage, apply,
 * verify, rollback, shutdown. This header is the core side of it.
 *
 * The important property is what is NOT here: there is no mention of IPVS,
 * ldirectord, HAProxy, OVS, gredist or PPPoE. The core sequences a
 * lifecycle and enforces the rules around it; what any of those steps MEANS
 * is entirely the module's business. That is what keeps the seam honest --
 * the first real provider is a test of the seam, and a seam that had to
 * learn about its first tenant is not a seam.
 *
 * The core keeps ownership of what the design says it owns: authorization,
 * transactions, audit, and the order of the steps. A module describes,
 * validates, renders, applies and verifies its own subsystem, and is given no
 * database handle, no shell and no way to skip a step (D1 8, D3 2).
 */
#ifndef SR_PROVIDER_H
#define SR_PROVIDER_H

#include "sr_db.h"
#include "sr_module.h"      /* sr_ctx, sr_module_ops, SR_PROVIDES_* */

/* Which lifecycle step a caller is asking for. Kept as an enum rather than a
 * string so the core can map it to the SR_PROVIDES_* bit without a lookup
 * table, and so an unknown name is a compile error rather than a runtime
 * surprise. */
typedef enum {
    SR_STEP_INIT = 0,
    SR_STEP_DISCOVER,
    SR_STEP_OBSERVE,
    SR_STEP_VALIDATE,
    SR_STEP_RENDER,
    SR_STEP_STAGE,
    SR_STEP_APPLY,
    SR_STEP_VERIFY,
    SR_STEP_ROLLBACK,
    SR_STEP_SHUTDOWN
} sr_step;

/* Loader accessors, defined in module.c. Taking a module's operations BY NAME
 * is what lets this layer be written once: the core never needs to know which
 * module it is driving, and no provider-specific symbol ever appears here. */
int                 sr_module_load_all(sr_db *db, const char *moddir,
                                      const char *actor_id, const char *tenant_id);
int                 sr_module_count(void);
const sr_module_ops *sr_module_ops_get(const char *name);
sr_ctx             *sr_module_ctx_get(const char *name);
uint64_t            sr_module_provides_get(const char *name);

/* Names for the wire and for the audit trail. */
const char *sr_step_name(sr_step step);

/* Map a step to its SR_PROVIDES_* bit, and to the sr_module_ops member that
 * implements it. Returns 0 / NULL for an unmapped step. */
uint64_t sr_step_provides_bit(sr_step step);
int       sr_step_invoke(sr_step step, const sr_module_ops *ops, sr_ctx *ctx,
                         const char *host_id, const char *object_type,
                         const char *json, char **out_text);

/* Is `name` a step this core understands at all? Callers use it to refuse an
 * unknown verb with a clear error instead of an "operation not supported". */
int sr_step_from_name(const char *name, sr_step *out);

/* One lifecycle step, dispatched generically.
 *
 * Refuses, rather than guessing, when: the module is not loaded, the module
 * does not advertise this step, the module declines the operation pointer,
 * or the actor lacks the capability. Each refusal is audited.
 *
 * Returns 0 on success. On success *out_text (if any) is an owned buffer.
 *
 * *out_err, when given, receives an owned explanation of any refusal: a
 * refusal that cannot say WHY is indistinguishable from a broken daemon, and
 * an operator holding one has no way to act on it. Every refusal below
 * therefore produces a sentence, not a code. */
int sr_provider_invoke(sr_db *db, const char *module_name, sr_step step,
                       const char *actor_id, const char *tenant_id,
                       const char *host_id, const char *object_type,
                       const char *json, char **out_text, char **out_err);

/* Run the whole lifecycle for one desired-state change, in the order the
 * design fixes, and let the core own the transaction.
 *
 *   discover -> snapshot the subsystem as it IS
 *   validate -> refuse here, before anything can be activated
 *   render   -> the module's rendering of the desired state
 *   stage    -> the module prepares, WITHOUT activating
 *   apply    -> the only step permitted to change the subsystem
 *   verify   -> read back and confirm
 *
 * If apply or verify fails, rollback is invoked and the outcome is recorded
 * as a real failure -- not a partial success. Desired and observed state are
 * separate throughout: a failed apply never rewrites desired state.
 *
 * *out_report is an owned JSON string describing what happened at each step.
 * Returns 0 only when every step succeeded, including verify. */
int sr_provider_transaction(sr_db *db, const char *module_name,
                            const char *actor_id, const char *tenant_id,
                            const char *host_id, const char *object_type,
                            const char *desired_json, char **out_report);

#endif /* SR_PROVIDER_H */
