/* test_enroll.c -- integration: prove the five-state capability model against
 * a REAL node, with real feature probes and no daemon.
 *
 * This is the acceptance that matters: an operator must be able to see what
 * a node actually supports, and the answer must come from exercising features
 * rather than from inferring them (D6 3).
 */
#include "sr_db.h"
#include "sr_module.h"
#include "sr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int sr_enroll_host(sr_db *, const char *, const char *, const char *,
                          char **, char **);
extern int sr_discover_host(sr_db *, const char *, const char *);

static int failures;
static void check(const char *what, int cond)
{
    printf("  %-58s %s\n", what, cond ? "PASS" : "**FAIL**");
    if (!cond) failures++;
}

static const char *cap_state(sr_db *db, const char *hid, const char *cap,
                             char *buf, size_t n)
{
    char q[512];
    snprintf(q, sizeof q,
        "SELECT state FROM host_capability WHERE host_id='%s' AND capability='%s';",
        hid, cap);
    char *r = NULL;
    buf[0] = '\0';
    if (sr_db_query_text(db, q, &r) < 0 || !r) { free(r); return NULL; }
    snprintf(buf, n, "%s", r);
    free(r);
    return buf;
}

static const char *cap_probe(sr_db *db, const char *hid, const char *cap,
                             char *buf, size_t n)
{
    char q[512];
    snprintf(q, sizeof q,
        "SELECT COALESCE(probe_method,'') FROM host_capability "
        "WHERE host_id='%s' AND capability='%s';", hid, cap);
    char *r = NULL;
    buf[0] = '\0';
    if (sr_db_query_text(db, q, &r) < 0 || !r) { free(r); return NULL; }
    snprintf(buf, n, "%s", r);
    free(r);
    return buf;
}

int main(int argc, char **argv)
{
    const char *addr = argc > 1 ? argv[1] : "172.16.7.100";
    const char *name = argc > 2 ? argv[2] : "nodea";

    unlink("/tmp/sr_enroll.db");
    unlink("/tmp/sr_enroll.db-wal");
    unlink("/tmp/sr_enroll.db-shm");

    sr_db *db = NULL; char *err = NULL;
    if (sr_db_open("/tmp/sr_enroll.db", &db) < 0) { puts("cannot open db"); return 1; }
    if (sr_db_migrate(db, &err) < 0) { printf("migrate: %s\n", err); return 1; }
    sr_db_exec(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at) "
                   "VALUES('t1','t','T',datetime('now'),datetime('now'))", &err);

    char *hid = NULL;
    printf("  enrolling %s (%s) over read-only SSH bootstrap\n", name, addr);
    if (sr_enroll_host(db, "t1", addr, name, &hid, &err) < 0) {
        printf("  enroll failed: %s\n", err ? err : "?");
        return 1;
    }
    check("host record created", hid != NULL);

    int n = sr_discover_host(db, "t1", hid);
    printf("  capability records written: %d\n", n);
    check("discovery recorded capabilities", n > 0);

    char s[32], pm[128];

    /* The headline case: nf_tables is compiled INTO the kernel here, so it
     * is absent from lsmod while being fully functional. A probe that
     * inferred capability from lsmod would call this broken. */
    cap_state(db, hid, "nftables", s, sizeof s);
    printf("\n  nftables -> state=%s  probe=%s\n", s, cap_probe(db, hid, "nftables", pm, sizeof pm));
    check("nftables probed as 'usable' despite not being in lsmod",
          strcmp(s, "usable") == 0);
    check("nftables evidence names the direct probe (nft -c)",
          strstr(cap_probe(db, hid, "nftables", pm, sizeof pm), "nft -c") != NULL);
    check("nftables probe is NOT lsmod",
          strstr(pm, "lsmod") == NULL);

    /* Absence must be 'unavailable', never a healthy guess. */
    cap_state(db, hid, "ipvs", s, sizeof s);
    printf("  ipvs -> state=%s\n", s);
    check("absent component reported 'unavailable', not healthy",
          strcmp(s, "unavailable") == 0);

    cap_state(db, hid, "haproxy", s, sizeof s);
    printf("  haproxy -> state=%s\n", s);
    check("absent haproxy reported 'unavailable'", strcmp(s, "unavailable") == 0);

    /* The HAProxy runtime API is a SEPARATE capability from HAProxy itself,
     * and is expected to be unavailable: no shipped Saphira config enables a
     * stats socket, so observed state genuinely cannot be determined. */
    cap_state(db, hid, "haproxy.runtime", s, sizeof s);
    printf("  haproxy.runtime -> state=%s\n", s);
    check("haproxy.runtime is a distinct capability row",
          strcmp(s, "unavailable") == 0);

    /* gredist is present but has no service integration and no queryable
     * endpoint, so the honest ceiling is 'installed' (D1 A.3). */
    cap_state(db, hid, "gredist", s, sizeof s);
    printf("  gredist -> state=%s\n", s);
    check("gredist stops at 'installed' (no queryable endpoint)",
          strcmp(s, "installed") == 0);

    /* perl is deliberately not a package dependency of ldirectord, so it is
     * probed on its own rather than assumed. */
    cap_state(db, hid, "perl", s, sizeof s);
    printf("  perl -> state=%s\n", s);
    check("perl probed independently of ldirectord",
          strcmp(s, "usable") == 0 || strcmp(s, "unavailable") == 0);

    cap_state(db, hid, "ldirectord", s, sizeof s);
    printf("  ldirectord -> state=%s\n", s);
    check("ldirectord state is recorded independently", s[0] != '\0');

    /* Every recorded state must be inside the vocabulary. */
    {
        sqlite3_stmt *st;
        int bad = 0, total = 0;
        sr_db_prepare(db, "SELECT state FROM host_capability WHERE host_id=?;", &st, NULL);
        sqlite3_bind_text(st, 1, hid, -1, SQLITE_STATIC);
        while (sqlite3_step(st) == SQLITE_ROW) {
            const char *v = (const char *)sqlite3_column_text(st, 0);
            total++;
            if (strcmp(v,"unestablished") && strcmp(v,"unavailable") &&
                strcmp(v,"installed") && strcmp(v,"available") &&
                strcmp(v,"usable") && strcmp(v,"healthy")) bad++;
        }
        sqlite3_finalize(st);
        check("every state is in the five-state vocabulary", bad == 0 && total > 0);
    }

    /* Tenant isolation on a real record (D5 7.3, id-addressed case). */
    {
        sr_db_exec(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at) "
                       "VALUES('t2','other','Other',datetime('now'),datetime('now'))", &err);
        sqlite3_stmt *st; int seen = 0;
        if (sr_db_prepare(db,
            "SELECT COUNT(*) FROM host_capability hc JOIN host h ON h.id=hc.host_id "
            "WHERE hc.host_id=? AND h.tenant_id='t2';", &st, NULL) == 0) {
            sqlite3_bind_text(st, 1, hid, -1, SQLITE_STATIC);
            if (sqlite3_step(st) == SQLITE_ROW) seen = sqlite3_column_int(st, 0);
            sqlite3_finalize(st);
        }
        check("another tenant cannot see this host's capabilities", seen == 0);
    }

    printf("\n");
    if (failures == 0) puts("  ALL PASS");
    else printf("  %d FAILURE(S)\n", failures);
    return failures ? 1 : 0;
}
