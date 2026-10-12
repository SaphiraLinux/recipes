/* main.c -- saphira-router entry point.
 *
 * One binary, several roles. The daemon owns the database; the CLI and the
 * TUI are clients of its API and never open it themselves (D1 3.2, D4 1).
 */
#include "sr.h"
#include "sr_db.h"
#include "sr_api.h"
#include "sr_auth.h"
#include "sr_rbac.h"
#include "sr_tui.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int  sr_module_load_all(sr_db *, const char *, const char *, const char *);
extern void sr_module_unload_all(void);
extern int  sr_tui_run(sr_db *, const char *);
#include "sr_cli.h"

#define SR_DEFAULT_DB   "/var/lib/saphira-router/router.db"
#define SR_DEFAULT_SOCK "/run/saphira-router/api.sock"
#define SR_DEFAULT_MODS "/usr/lib/saphira-router/modules"

static volatile int g_stop;
static void on_sig(int s) { (void)s; g_stop = 1; }

static const char *env_or(const char *k, const char *dflt)
{
    const char *v = getenv(k);
    return (v && *v) ? v : dflt;
}

static void usage(void)
{
    fputs(
"  saphira-router -- Saphira Linux multi-tenant control plane\n"
"\n"
"  Roles:\n"
"    init                     create the database and bootstrap the first tenant\n"
"    daemon                   run the control-plane service (the sole writer)\n"
"    tui                      the primary human interface\n"
"    <anything else>          the CLI, a thin client of the daemon's API\n"
"\n"
"  Examples:\n"
"    saphira-router init --user admin --password ...\n"
"    saphira-router daemon &\n"
"    saphira-router login --user admin\n"
"    saphira-router host list --json\n"
"    saphira-router host enroll --address 172.16.7.100 --json\n"
"    saphira-router host caps <host_id> --json\n"
"    saphira-router module list --json\n"
"    saphira-router provider transaction --module ipvs --spec '<desired>'\n"
"    saphira-router provider step observe --module ipvs\n"
"    saphira-router provider invoke --module ipvs --step verify\n"
"\n"
"  Environment:\n"
"    SR_DB, SR_SOCK, SR_MODULES\n", stderr);
}

int main(int argc, char **argv)
{
    if (argc < 2) { usage(); return SR_ERR_USAGE; }
    const char *dbpath  = env_or("SR_DB",   SR_DEFAULT_DB);
    const char *sock    = env_or("SR_SOCK", SR_DEFAULT_SOCK);
    const char *moddir  = env_or("SR_MODULES", SR_DEFAULT_MODS);

    if (strcmp(argv[1], "init") == 0) {
        const char *user = "admin", *pass = NULL;
        for (int i = 2; i < argc - 1; i++) {
            if (strcmp(argv[i], "--user") == 0) user = argv[++i];
            else if (strcmp(argv[i], "--password") == 0) pass = argv[++i];
        }
        if (!pass) { fputs("init: --password is required\n", stderr); return SR_ERR_USAGE; }

        sr_db *db = NULL; char *err = NULL;
        if (sr_db_open(dbpath, &db) < 0) return SR_ERR_FAILED;
        if (sr_db_migrate(db, &err) < 0) {
            fprintf(stderr, "migrate: %s\n", err ? err : "?"); return SR_ERR_FAILED;
        }
        char *tid = NULL;
        if (sr_db_query_text(db, "SELECT id FROM tenant LIMIT 1;", &tid) < 0 || !tid) {
            char t[SR_MAX_ID]; sr_gen_id(t, sizeof t);
            sqlite3_stmt *st;
            sr_db_prepare(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at)"
                             " VALUES(?,'default','Default Tenant',datetime('now'),datetime('now'));", &st, &err);
            sqlite3_bind_text(st, 1, t, -1, SQLITE_STATIC); sqlite3_step(st); sqlite3_finalize(st);
            tid = sr_xstrdup(t);
        }
        char *uid = NULL;
        if (sr_auth_create_user(db, user, pass, &uid, &err) < 0) {
            fprintf(stderr, "init: %s\n", err ? err : "cannot create user"); return SR_ERR_FAILED;
        }
        /* The bootstrap administrator is a role with an ENUMERATED grant, not
         * a wildcard. New capabilities do not join it automatically (D5 5). */
        char *rid = NULL;
        sr_rbac_create_role(db, tid, "admin", "Bootstrap administrator", &rid, &err);
        sr_rbac_assign(db, uid, rid, tid, &err);
        static const char *bootstrap[] = {
            "tenant.read","tenant.manage","user.create","user.read","user.manage",
            "role.create","role.read","role.grant","host.enroll","host.read",
            "host.manage","audit.read","audit.export","transaction.read",
            "transaction.apply","transaction.rollback","module.read",
            "secret.read","secret.manage", NULL };
        for (int i = 0; bootstrap[i]; i++) sr_rbac_grant(db, rid, bootstrap[i], &err);
        printf("initialised %s\n  tenant %s\n  user    %s (role: admin, %d capabilities)\n",
               dbpath, tid, user, sr_rbac_effective_count(db, uid, tid));
        sr_db_close(db);
        return SR_OK;
    }

    if (strcmp(argv[1], "daemon") == 0) {
        sr_db *db = NULL; char *err = NULL;
        if (sr_db_open(dbpath, &db) < 0) return SR_ERR_FAILED;
        if (sr_db_migrate(db, &err) < 0) {
            fprintf(stderr, "migrate: %s\n", err ? err : "?"); return SR_ERR_FAILED;
        }
        /* Modules are loaded for a service context so describe() is gathered
         * before any client connects. The core is usable with none installed. */
        char *tid = NULL;
        if (sr_db_query_text(db, "SELECT id FROM tenant LIMIT 1;", &tid) < 0) tid = NULL;
        int n = sr_module_load_all(db, moddir, "system", tid ? tid : "-");
        sr_log(SR_LOG_INFO, "module directory %s: %d module(s) loaded", moddir, n);
        signal(SIGINT, on_sig);
        signal(SIGTERM, on_sig);
        int rc = sr_api_serve(db, sock, &g_stop);
        sr_db_close(db);
        return rc < 0 ? SR_ERR_FAILED : SR_OK;
    }

    if (strcmp(argv[1], "tui") == 0) {
        /* The TUI is a CLIENT: it holds no database handle and writes no
         * state. Everything it shows comes from the API (D1 3.2, D9 3). */
        return sr_tui_main(argc - 1, argv + 1, sock);
    }

    /* everything else is the CLI */
    return sr_cli_run(argc - 1, argv + 1);
}
