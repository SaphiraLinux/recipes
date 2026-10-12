/* sr_audit.h -- the audit trail (D4 12, D3 6).
 *
 * Append-only in intent: this is the forensic record of who did what, and it
 * is never edited by normal operations. Core-mediated: modules reach it only
 * through sr_ctx.audit, so an audited action cannot bypass the record.
 */
#ifndef SR_AUDIT_H
#define SR_AUDIT_H

#include "sr.h"
#include "sr_db.h"

/* Outcomes recorded on every event. 'denied' is as important as 'success':
 * a refused action must be as visible as a permitted one (D3 6). */
#define SR_AUDIT_SUCCESS "success"
#define SR_AUDIT_DENIED  "denied"
#define SR_AUDIT_FAILED  "failed"

/* tenant_id, actor_id and session_id may be NULL for events that precede a
 * tenant context -- notably an authentication FAILURE, where by definition
 * no session and possibly no tenant is known yet. */
int sr_audit(sr_db *db, const char *tenant_id, const char *actor_id,
             const char *session_id, const char *action,
             const char *object_type, const char *object_id,
             const char *outcome, const char *source_addr,
             const char *detail);

/* Convenience for the very common authorization-decision case. */
int sr_audit_authz(sr_db *db, const char *tenant_id, const char *actor_id,
                   const char *session_id, const char *capability,
                   int allowed, const char *source_addr);

int sr_audit_count(sr_db *db, const char *action_filter, const char *outcome_filter);

#endif
