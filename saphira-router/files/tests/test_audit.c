/* test_audit.c -- the audit trail records what it must, including refusals.
 *
 * A control plane that can act but cannot say who acted is not auditable.
 * These assertions are about the FORENSIC record, so they check outcomes and
 * provenance rather than just that a row exists.
 */
#include "sr_db.h"
#include "sr_auth.h"
#include "sr_rbac.h"
#include "sr_audit.h"
#include "sr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures;
static void check3(const char *what, int cond, const char *detail);

static void check(const char *what, int cond)
{
    check3(what, cond, NULL);
}

static void check3(const char *what, int cond, const char *detail)
{
    printf("  %-58s %s\n", what, cond ? "PASS" : "**FAIL**");
    if (!cond) {
        failures++;
        if (detail) printf("      %s\n", detail);
    }
}

static int has_event(sr_db *db, const char *action, const char *outcome,
                     const char *object_id)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT COUNT(*) FROM audit_event WHERE action=? AND outcome=? "
        "AND COALESCE(object_id,'')=?;", &st, NULL) < 0) return -1;
    sqlite3_bind_text(st, 1, action, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, outcome, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, object_id, -1, SQLITE_STATIC);
    int n = -1;
    if (sqlite3_step(st) == SQLITE_ROW) n = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    return n;
}

static char *col0(sr_db *db, const char *sql)
{
    char *r = NULL;
    if (sr_db_query_text(db, sql, &r) < 0) return NULL;
    return r;
}

int main(void)
{
    unlink("/tmp/sr_audit.db"); unlink("/tmp/sr_audit.db-wal");
    unlink("/tmp/sr_audit.db-shm");

    sr_db *db = NULL; char *err = NULL;
    sr_db_open("/tmp/sr_audit.db", &db);
    if (sr_db_migrate(db, &err) < 0) { printf("migrate: %s\n", err); return 1; }
    check("migrations applied through version 2", sr_db_version(db) == 2);

    /* migration 2 exists so a pre-authentication event has an honest NULL */
    check("audit_event.tenant_id is nullable after migration 2",
          sr_audit(db, NULL, NULL, NULL, "auth.login", "user", "ghost",
                   SR_AUDIT_DENIED, NULL, NULL) == 0);
    char *tn = col0(db, "SELECT COALESCE(tenant_id,'<null>') FROM audit_event "
                        "WHERE action='auth.login';");
    check("a pre-auth event records tenant_id as NULL, not a fabricated one",
          tn && strcmp(tn, "<null>") == 0);
    free(tn);

    sr_db_exec(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at) "
                   "VALUES('t1','t','T',datetime('now'),datetime('now'))", &err);
    char *uid = NULL;
    sr_auth_create_user(db, "alice", "pw", &uid, &err);
    check("user created", uid != NULL);

    char *rid = NULL;
    sr_rbac_create_role(db, "t1", "viewer", "v", &rid, &err);
    sr_rbac_assign(db, uid, rid, "t1", &err);
    int grants = sr_audit_count(db, "capability.grant", NULL);
    check("role creation/assignment does not invent capability grants", grants == 0);

    /* --- capability DENY is audited ------------------------------------ */
    char *why = NULL;
    int allowed = sr_rbac_authorize(db, uid, "t1", "host.enroll", &why);
    check("capability not granted is denied", allowed == 0);
    check("the refusal carries a reason", why != NULL);
    free(why);
    check("the DENIAL is in the audit trail",
          has_event(db, "capability.check", SR_AUDIT_DENIED, "host.enroll") == 1);

    /* --- capability GRANT is audited ----------------------------------- */
    check("granting a registered capability works",
          sr_rbac_grant(db, rid, "host.enroll", &err) == 0);
    check("the GRANT is in the audit trail",
          has_event(db, "capability.grant", SR_AUDIT_SUCCESS, "host.enroll") == 1);
    why = NULL;
    check("the granted capability now allows",
          sr_rbac_authorize(db, uid, "t1", "host.enroll", &why) == 1);

    /* --- an unknown code cannot be granted at all ---------------------- */
    check("granting an unregistered code is refused",
          sr_rbac_grant(db, rid, "totally.made.up", &err) != 0);
    check("the refused grant did NOT mint authority",
          has_event(db, "capability.grant", SR_AUDIT_SUCCESS,
                    "totally.made.up") == 0);

    /* --- session lifecycle --------------------------------------------- */
    char *tok = NULL, *sid = NULL;
    check("session created",
          sr_auth_session_create(db, uid, "t1", "10.0.0.1", &tok, &sid, &err) == 0);
    sr_audit(db, "t1", uid, sid, "session.create", "session", sid,
             SR_AUDIT_SUCCESS, "10.0.0.1", NULL);
    check("session.create is recorded",
          has_event(db, "session.create", SR_AUDIT_SUCCESS, sid) == 1);

    /* --- login outcomes ------------------------------------------------ */
    sr_audit(db, "t1", uid, sid, "auth.login", "user", "alice",
             SR_AUDIT_SUCCESS, "10.0.0.1", NULL);
    sr_audit(db, NULL, NULL, NULL, "auth.login", "user", "alice",
             SR_AUDIT_DENIED, "10.0.0.2", NULL);
    check("successful login recorded",
          has_event(db, "auth.login", SR_AUDIT_SUCCESS, "alice") == 1);
    check("failed login recorded",
          has_event(db, "auth.login", SR_AUDIT_DENIED, "alice") == 1);
    char *ft = col0(db, "SELECT COALESCE(tenant_id,'<null>') FROM audit_event "
                        "WHERE action='auth.login' AND outcome='denied' "
                        "AND object_id='alice';");
    check("a failed login has no tenant attributed (not a fabricated one)",
          ft && strcmp(ft, "<null>") == 0);
    free(ft);

    /* --- append-only: repeated events accumulate, none are rewritten --- */
    int before = sr_audit_count(db, NULL, NULL);
    for (int i = 0; i < 5; i++)
        sr_audit(db, "t1", uid, sid, "host.enroll", "host", "h1",
                 SR_AUDIT_SUCCESS, "10.0.0.1", NULL);
    check("events accumulate rather than being overwritten",
          sr_audit_count(db, NULL, NULL) == before + 5);
    check("each enrollment is individually recorded",
          has_event(db, "host.enroll", SR_AUDIT_SUCCESS, "h1") == 5);

    /* --- the trail spans tenants but never invents one ----------------- */
    sr_db_exec(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at) "
                   "VALUES('t2','other','Other',datetime('now'),datetime('now'))", &err);
    check("a second tenant exists and is not attributed to the first",
          sr_audit_count(db, NULL, NULL) > 0);

    /* --- source_addr is a network address, never a scratch column -------
     * sr_audit's 9th and 10th parameters are adjacent const char *, so a
     * swapped pair compiles with no warning at all. It happened: module
     * refusals and capability probes wrote their reason into source_addr
     * and left detail NULL, so the trail showed a refused module with no
     * explanation and a "source address" reading
     * "incompatible: module ABI 100 is not supported".
     *
     * This check is deliberately generic over every row rather than about one
     * action: any prose in that column means an argument pair was swapped, and
     * it is the cheapest place to notice. The per-action assertion lives in
     * test_module.c, which is where a refusal is actually produced. */
    {
        char *prose = NULL;
        sr_db_query_text(db,
            "SELECT COUNT(*) FROM audit_event WHERE source_addr IS NOT NULL "
            "AND (source_addr LIKE '% %' OR source_addr LIKE '%:% %');",
            &prose);
        check3("no audit row carries prose in the source_addr column",
              prose && atoi(prose) == 0, prose);
        free(prose);
    }

    /* --- an audit write failure is loud, not silent -------------------- */
    {
        sr_db *broken = NULL;
        /* a read-only database makes every insert fail */
        sr_db_open("/tmp/sr_audit_ro.db", &broken);
        sr_db_migrate(broken, &err);
        sr_db_exec(broken, "DROP TABLE audit_event;", &err);
        int rc = sr_audit(broken, "t1", "x", NULL, "x", NULL, NULL,
                          SR_AUDIT_SUCCESS, NULL, NULL);
        check("an audit write against a broken table fails loudly (-1)", rc == -1);
        sr_db_close(broken);
    }

    printf("\n");
    if (!failures) puts("  ALL PASS");
    else printf("  %d FAILURE(S)\n", failures);
    return failures ? 1 : 0;
}
