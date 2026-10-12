/* audit.c -- the append-only audit trail.
 *
 * Every configuration change records actor, object, before/after, outcome and
 * transaction (D4 12, D3 6). Denials are recorded as durably as successes:
 * "who tried and was refused" has to be answerable, so an authorization check
 * that returns no still writes a row.
 *
 * The core is the only writer, so an audited action cannot skip the record.
 * Modules reach this only through sr_ctx.audit (D2 5).
 */

#include "sr_audit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int sr_audit(sr_db *db, const char *tenant_id, const char *actor_id,
             const char *session_id, const char *action,
             const char *object_type, const char *object_id,
             const char *outcome, const char *source_addr,
             const char *detail)
{
    if (!db || !action || !outcome) return -1;

    char id[SR_MAX_ID];
    sr_gen_id(id, sizeof id);

    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO audit_event(id,tenant_id,actor_id,session_id,action,"
        "object_type,object_id,outcome,source_addr,detail,created_at) "
        "VALUES(?,?,?,?,?,?,?,?,?,?,datetime('now'));", &st, NULL) < 0)
        return -1;

    sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);

    /* NULL rather than a sentinel: a pre-authentication event genuinely has no
     * tenant, and inventing one would make the trail lie. */
    if (tenant_id)  sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    else            sqlite3_bind_null(st, 2);
    if (actor_id)   sqlite3_bind_text(st, 3, actor_id, -1, SQLITE_STATIC);
    else            sqlite3_bind_null(st, 3);
    if (session_id) sqlite3_bind_text(st, 4, session_id, -1, SQLITE_STATIC);
    else            sqlite3_bind_null(st, 4);

    sqlite3_bind_text(st, 5, action, -1, SQLITE_STATIC);
    if (object_type) sqlite3_bind_text(st, 6, object_type, -1, SQLITE_STATIC);
    else             sqlite3_bind_null(st, 6);
    if (object_id)   sqlite3_bind_text(st, 7, object_id, -1, SQLITE_STATIC);
    else             sqlite3_bind_null(st, 7);
    sqlite3_bind_text(st, 8, outcome, -1, SQLITE_STATIC);
    if (source_addr) sqlite3_bind_text(st, 9, source_addr, -1, SQLITE_STATIC);
    else             sqlite3_bind_null(st, 9);
    if (detail) sqlite3_bind_text(st, 10, detail, -1, SQLITE_STATIC);
    else        sqlite3_bind_null(st, 10);

    int rc = sqlite3_step(st);
    sqlite3_finalize(st);

    if (rc != SQLITE_DONE) {
        /* An audit failure must never be silent: a control plane that cannot
         * record what it did is worse than one that refuses the action, so at
         * minimum this is loud. */
        sr_log(SR_LOG_ERROR, "audit write FAILED for action=%s: %s",
               action, sqlite3_errmsg(sr_db_handle(db)));
        return -1;
    }
    return 0;
}

int sr_audit_authz(sr_db *db, const char *tenant_id, const char *actor_id,
                   const char *session_id, const char *capability,
                   int allowed, const char *source_addr)
{
    return sr_audit(db, tenant_id, actor_id, session_id,
                    "capability.check", "capability", capability,
                    allowed ? SR_AUDIT_SUCCESS : SR_AUDIT_DENIED, source_addr,
                    NULL);
}

int sr_audit_count(sr_db *db, const char *action_filter,
                   const char *outcome_filter)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT COUNT(*) FROM audit_event "
        "WHERE (?1 IS NULL OR action=?1) AND (?2 IS NULL OR outcome=?2);",
        &st, NULL) < 0) return -1;
    if (action_filter)  sqlite3_bind_text(st, 1, action_filter, -1, SQLITE_STATIC);
    else                sqlite3_bind_null(st, 1);
    if (outcome_filter) sqlite3_bind_text(st, 2, outcome_filter, -1, SQLITE_STATIC);
    else                sqlite3_bind_null(st, 2);
    int n = -1;
    if (sqlite3_step(st) == SQLITE_ROW) n = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    return n;
}
