/* rbac.c -- explicit, namespaced, deny-by-default capabilities. */

#include "sr_rbac.h"
#include "sr_db.h"
#include "sr_audit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int sr_rbac_authorize(sr_db *db, const char *user_id, const char *tenant_id,
                      const char *capability, char **reason)
{
    if (reason) *reason = NULL;

    /* Deny by default: the check is a lookup and a miss is a denial. There
     * is no "well-known" set that could absorb a new capability, and no
     * wildcard (D5 5). */
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT 1 FROM user_role ur "
        "JOIN role_capability rc ON rc.role_id = ur.role_id "
        "WHERE ur.user_id=? AND ur.tenant_id=? AND rc.capability_code=? "
        "LIMIT 1;", &st, NULL) < 0)
        return 0;

    sqlite3_bind_text(st, 1, user_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, capability, -1, SQLITE_STATIC);

    int allowed = 0;
    if (sqlite3_step(st) == SQLITE_ROW) allowed = 1;
    sqlite3_finalize(st);

    if (!allowed) {
        if (reason) {
            char buf[256];
            snprintf(buf, sizeof buf,
                     "missing capability '%s' for this user in this tenant",
                     capability);
            *reason = sr_xstrdup(buf);
        }
        /* A refusal must be as visible as a permission: "who tried and was
         * denied" has to be answerable (D3 6). Successes are recorded by the
         * action that was permitted, not twice here. */
        sr_audit_authz(db, tenant_id, user_id, NULL, capability, 0, NULL);
    }
    return allowed;
}

int sr_rbac_grant(sr_db *db, const char *role_id, const char *capability,
                  char **err)
{
    /* Granting a capability that is not in the vocabulary is refused: the
     * registry is the source of truth, so a typo cannot mint authority.
     * Bound statement required -- see the note on sr_db_query_text. */
    int known = 0;
    sqlite3_stmt *ck = NULL;
    if (sr_db_prepare(db, "SELECT 1 FROM capability WHERE code=?;", &ck, err) < 0)
        return -1;
    sqlite3_bind_text(ck, 1, capability, -1, SQLITE_STATIC);
    if (sqlite3_step(ck) == SQLITE_ROW) known = 1;
    sqlite3_finalize(ck);
    if (!known) {
        if (err) *err = sr_xstrdup("unknown capability code");
        return -1;
    }

    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT OR IGNORE INTO role_capability(role_id,capability_code) "
        "VALUES(?,?);", &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, role_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, capability, -1, SQLITE_STATIC);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    if (rc == SQLITE_DONE)
        sr_audit(db, NULL, NULL, NULL, "capability.grant", "capability",
                 capability, SR_AUDIT_SUCCESS, NULL, NULL);
    return rc == SQLITE_DONE ? 0 : -1;
}

int sr_rbac_revoke(sr_db *db, const char *role_id, const char *capability,
                   char **err)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "DELETE FROM role_capability WHERE role_id=? AND capability_code=?;",
        &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, role_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, capability, -1, SQLITE_STATIC);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    if (rc == SQLITE_DONE)
        sr_audit(db, NULL, NULL, NULL, "capability.revoke", "capability",
                 capability, SR_AUDIT_SUCCESS, NULL, NULL);
    return rc == SQLITE_DONE ? 0 : -1;
}

int sr_rbac_create_role(sr_db *db, const char *tenant_id, const char *name,
                        const char *description, char **out_id, char **err)
{
    char id[SR_MAX_ID];
    sr_gen_id(id, sizeof id);
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO role(id,tenant_id,name,description,is_system) "
        "VALUES(?,?,?,?,0);", &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);
    if (tenant_id) sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 2);
    sqlite3_bind_text(st, 3, name, -1, SQLITE_STATIC);
    if (description) sqlite3_bind_text(st, 4, description, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 4);
    if (sqlite3_step(st) != SQLITE_DONE) { sqlite3_finalize(st);
        if (err) *err = sr_xstrdup("cannot create role");
        return -1; }
    sqlite3_finalize(st);
    *out_id = sr_xstrdup(id);
    return 0;
}

int sr_rbac_assign(sr_db *db, const char *user_id, const char *role_id,
                   const char *tenant_id, char **err)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT OR IGNORE INTO user_role(user_id,role_id,tenant_id) "
        "VALUES(?,?,?);", &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, user_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, role_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, tenant_id, -1, SQLITE_STATIC);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    return rc == SQLITE_DONE ? 0 : -1;
}

int sr_rbac_effective_count(sr_db *db, const char *user_id,
                            const char *tenant_id)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT COUNT(DISTINCT rc.capability_code) FROM user_role ur "
        "JOIN role_capability rc ON rc.role_id=ur.role_id "
        "WHERE ur.user_id=? AND ur.tenant_id=?;", &st, NULL) < 0)
        return -1;
    sqlite3_bind_text(st, 1, user_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    int n = -1;
    if (sqlite3_step(st) == SQLITE_ROW) n = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    return n;
}
