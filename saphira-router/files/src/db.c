/* db.c -- core-owned SQLite access and the migration chain. */

#include "sr_db.h"
#include "sr_module.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

struct sr_db {
    sqlite3 *h;
    char    *path;
};

/* ------------------------------------------------------------- helpers */

static char *xstrdup_or_null(const char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s);
    char *p = malloc(n + 1);
    if (!p) return NULL;
    memcpy(p, s, n + 1);
    return p;
}

static void set_err(char **err, const char *fmt, ...)
{
    if (!err) return;
    va_list ap;
    va_start(ap, fmt);
    char buf[SR_MAX_TEXT];
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    free(*err);
    *err = xstrdup_or_null(buf);
}

int sr_db_exec(sr_db *db, const char *sql, char **err)
{
    char *msg = NULL;
    if (sqlite3_exec(db->h, sql, NULL, NULL, &msg) != SQLITE_OK) {
        set_err(err, "%s", msg ? msg : "sqlite error");
        if (msg) sqlite3_free(msg);
        return -1;
    }
    return 0;
}

int sr_db_prepare(sr_db *db, const char *sql, sqlite3_stmt **st, char **err)
{
    if (sqlite3_prepare_v2(db->h, sql, -1, st, NULL) != SQLITE_OK) {
        set_err(err, "%s", sqlite3_errmsg(db->h));
        return -1;
    }
    return 0;
}

int sr_db_begin(sr_db *db, char **err)   { return sr_db_exec(db, "BEGIN IMMEDIATE", err); }
int sr_db_commit(sr_db *db, char **err)  { return sr_db_exec(db, "COMMIT", err); }
int sr_db_rollback(sr_db *db)            { sqlite3_exec(db->h, "ROLLBACK", NULL, NULL, NULL); return 0; }

int sr_db_query_text(sr_db *db, const char *sql, char **out)
{
    sqlite3_stmt *st = NULL;
    *out = NULL;
    if (sqlite3_prepare_v2(db->h, sql, -1, &st, NULL) != SQLITE_OK) return -1;
    int rc = 0;
    if (sqlite3_step(st) == SQLITE_ROW) {
        const unsigned char *t = sqlite3_column_text(st, 0);
        *out = t ? xstrdup_or_null((const char *)t) : NULL;
    } else {
        rc = -1;
    }
    sqlite3_finalize(st);
    return rc;
}

int sr_db_version(sr_db *db)
{
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db->h, "PRAGMA user_version;", -1, &st, NULL) != SQLITE_OK)
        return -1;
    int v = -1;
    if (sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    return v;
}

/* ---------------------------------------------------------- open/close */

int sr_db_open(const char *path, sr_db **out)
{
    sr_db *db = calloc(1, sizeof *db);
    if (!db) return -1;
    db->path = xstrdup_or_null(path);

    int rc = sqlite3_open_v2(path, &db->h,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
    if (rc != SQLITE_OK) {
        sr_log(SR_LOG_ERROR, "sqlite open failed: %s", sqlite3_errmsg(db->h));
        sqlite3_close(db->h);
        free(db->path);
        free(db);
        return -1;
    }
    sqlite3_busy_timeout(db->h, 30000);

    /* Concurrency WITHIN the control plane (D4 1). This is not permission
     * for clients to write -- there is one authority for writes. */
    sqlite3_exec(db->h, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    sqlite3_exec(db->h, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);
    sqlite3_exec(db->h, "PRAGMA synchronous=FULL;", NULL, NULL, NULL);

    *out = db;
    return 0;
}

void sr_db_close(sr_db *db)
{
    if (!db) return;
    if (db->h) sqlite3_close(db->h);
    free(db->path);
    free(db);
}

sqlite3 *sr_db_handle(sr_db *db) { return db ? db->h : NULL; }

/* ---------------------------------------------------------- migrations */

/* Migration 1: the base schema.
 *
 * host_capability is created ALREADY in its amended shape -- with state,
 * evidence, probe_method and checked_at. This is the D6 amendment applied
 * as a real migration at materialisation time, rather than an edit to the
 * design history (D6 section 4). A fresh schema needs no second migration
 * to add columns it was designed with.
 *
 * probe_method is constrained: a 'usable'/'healthy' row must name a direct
 * feature probe, never a proxy signal such as lsmod or a package query
 * (D6 3.1). The core enforces that on write, not by convention.
 */
/* Migration 1: the base schema, as an array of COMPLETE statements run in
 * one transaction. host_capability is created already in its amended
 * shape -- state, evidence, probe_method, checked_at -- which is the
 * D6 amendment applied as a real migration at materialisation time
 * rather than an edit to the design history (D6 4). A fresh schema
 * needs no second migration to add columns it was designed with.
 *
 * The state CHECK is what makes D6 3.1 enforceable: a usable/healthy
 * row must name a direct feature probe, never a proxy signal.
 */
static const char *const MIGRATION_1[] = {
  "CREATE TABLE schema_migration ("
  "  version INTEGER PRIMARY KEY,"
  "  name TEXT NOT NULL,"
  "  checksum TEXT NOT NULL,"
  "  applied_at TEXT NOT NULL)",
  "CREATE TABLE tenant ("
  "  id TEXT PRIMARY KEY,"
  "  slug TEXT NOT NULL UNIQUE,"
  "  name TEXT NOT NULL,"
  "  status TEXT NOT NULL DEFAULT 'active',"
  "  created_at TEXT NOT NULL,"
  "  updated_at TEXT NOT NULL)",
  "CREATE TABLE app_user ("
  "  id TEXT PRIMARY KEY,"
  "  username TEXT NOT NULL UNIQUE,"
  "  email TEXT,"
  "  password_algo TEXT NOT NULL DEFAULT 'argon2id',"
  "  password_hash TEXT NOT NULL,"
  "  failed_attempts INTEGER NOT NULL DEFAULT 0,"
  "  locked_until TEXT,"
  "  last_login_at TEXT,"
  "  status TEXT NOT NULL DEFAULT 'active',"
  "  created_at TEXT NOT NULL,"
  "  updated_at TEXT NOT NULL)",
  "CREATE TABLE role ("
  "  id TEXT PRIMARY KEY,"
  "  tenant_id TEXT REFERENCES tenant(id),"
  "  name TEXT NOT NULL,"
  "  description TEXT,"
  "  is_system INTEGER NOT NULL DEFAULT 0,"
  "  UNIQUE(tenant_id, name))",
  "CREATE TABLE capability ("
  "  code TEXT PRIMARY KEY,"
  "  description TEXT)",
  "CREATE TABLE role_capability ("
  "  role_id TEXT NOT NULL REFERENCES role(id),"
  "  capability_code TEXT NOT NULL REFERENCES capability(code),"
  "  PRIMARY KEY(role_id, capability_code))",
  "CREATE TABLE user_role ("
  "  user_id TEXT NOT NULL REFERENCES app_user(id),"
  "  role_id TEXT NOT NULL REFERENCES role(id),"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  PRIMARY KEY(user_id, role_id, tenant_id))",
  "CREATE TABLE session ("
  "  id TEXT PRIMARY KEY,"
  "  user_id TEXT NOT NULL REFERENCES app_user(id),"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  token_hash TEXT NOT NULL UNIQUE,"
  "  source_addr TEXT,"
  "  created_at TEXT NOT NULL,"
  "  expires_at TEXT NOT NULL,"
  "  last_seen_at TEXT,"
  "  revoked_at TEXT)",
  "CREATE TABLE host ("
  "  id TEXT PRIMARY KEY,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  hostname TEXT NOT NULL,"
  "  address_v4 TEXT,"
  "  address_v6 TEXT,"
  "  os_name TEXT,"
  "  os_version TEXT,"
  "  arch TEXT,"
  "  init_system TEXT,"
  "  drone_version TEXT,"
  "  identity_fingerprint TEXT,"
  "  status TEXT NOT NULL DEFAULT 'unknown',"
  "  enrolled_at TEXT,"
  "  last_seen_at TEXT,"
  "  UNIQUE(tenant_id, hostname))",
  "CREATE TABLE host_capability ("
  "  host_id TEXT NOT NULL REFERENCES host(id),"
  "  capability TEXT NOT NULL,"
  "  state TEXT NOT NULL DEFAULT 'unestablished'"
  "    CHECK(state IN ('unestablished','unavailable','installed','available','usable','healthy')),"
  "  version TEXT,"
  "  evidence TEXT,"
  "  probe_method TEXT,"
  "  detail TEXT,"
  "  checked_at TEXT NOT NULL,"
  "  PRIMARY KEY(host_id, capability))",
  "CREATE TABLE host_package ("
  "  host_id TEXT NOT NULL REFERENCES host(id),"
  "  name TEXT NOT NULL,"
  "  version TEXT,"
  "  discovered_at TEXT NOT NULL,"
  "  PRIMARY KEY(host_id, name))",
  "CREATE TABLE desired_state ("
  "  object_type TEXT NOT NULL,"
  "  object_id TEXT NOT NULL,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  desired_json TEXT NOT NULL,"
  "  spec_revision INTEGER NOT NULL,"
  "  updated_by TEXT REFERENCES app_user(id),"
  "  updated_at TEXT NOT NULL,"
  "  PRIMARY KEY(object_type, object_id))",
  "CREATE TABLE observed_state ("
  "  object_type TEXT NOT NULL,"
  "  object_id TEXT NOT NULL,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  observed_json TEXT NOT NULL,"
  "  health TEXT NOT NULL,"
  "  source TEXT NOT NULL,"
  "  observed_at TEXT NOT NULL,"
  "  detail TEXT,"
  "  PRIMARY KEY(object_type, object_id))",
  "CREATE TABLE audit_event ("
  "  id TEXT PRIMARY KEY,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  actor_id TEXT REFERENCES app_user(id),"
  "  session_id TEXT REFERENCES session(id),"
  "  action TEXT NOT NULL,"
  "  object_type TEXT,"
  "  object_id TEXT,"
  "  outcome TEXT NOT NULL,"
  "  source_addr TEXT,"
  "  before_json TEXT,"
  "  after_json TEXT,"
  "  txn_id TEXT,"
  "  detail TEXT,"
  "  created_at TEXT NOT NULL)",
  "CREATE INDEX audit_event_tenant_time ON audit_event(tenant_id, created_at)",
  "CREATE INDEX audit_event_object ON audit_event(object_type, object_id)",
  "CREATE TABLE module_registry ("
  "  module_name TEXT NOT NULL,"
  "  module_version TEXT NOT NULL,"
  "  abi_version INTEGER NOT NULL,"
  "  provides_mask INTEGER NOT NULL,"
  "  requires_mask INTEGER NOT NULL,"
  "  state TEXT NOT NULL CHECK(state IN ('loaded','refused','incompatible','disabled','stale')),"
  "  diagnostic TEXT,"
  "  last_seen_at TEXT NOT NULL,"
  "  PRIMARY KEY(module_name, module_version))",
  "CREATE TABLE provider_instance ("
  "  id TEXT PRIMARY KEY,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  name TEXT NOT NULL,"
  "  module_name TEXT NOT NULL,"
  "  scope_host_id TEXT REFERENCES host(id),"
  "  scope TEXT,"
  "  capabilities TEXT,"
  "  status TEXT NOT NULL DEFAULT 'active',"
  "  created_at TEXT NOT NULL,"
  "  UNIQUE(tenant_id, name))",
  "CREATE TABLE resource_binding ("
  "  id TEXT PRIMARY KEY,"
  "  tenant_id TEXT NOT NULL REFERENCES tenant(id),"
  "  provider_instance_id TEXT NOT NULL REFERENCES provider_instance(id),"
  "  resource_type TEXT NOT NULL,"
  "  resource_id TEXT NOT NULL,"
  "  native_id TEXT,"
  "  native_type TEXT,"
  "  attributes TEXT,"
  "  bound_at TEXT NOT NULL,"
  "  UNIQUE(resource_type, resource_id))",
  "CREATE INDEX resource_binding_instance ON resource_binding(provider_instance_id)",
  "INSERT INTO capability(code, description) VALUES ('tenant.create','tenant.create'),('tenant.read','tenant.read'),('tenant.manage','tenant.manage'),('user.create','user.create'),('user.read','user.read'),('user.manage','user.manage'),('role.create','role.create'),('role.read','role.read'),('role.grant','role.grant'),('host.enroll','host.enroll'),('host.read','host.read'),('host.manage','host.manage'),('audit.read','audit.read'),('audit.export','audit.export'),('transaction.read','transaction.read'),('transaction.apply','transaction.apply'),('transaction.rollback','transaction.rollback'),('module.read','module.read'),('secret.read','secret.read'),('secret.manage','secret.manage')",
  NULL
};

/* Migration 2: allow pre-authentication audit events.
 *
 * audit_event.tenant_id was NOT NULL, but an authentication FAILURE has by
 * definition no session and possibly no tenant -- there is nothing to
 * attribute it to. Inventing a tenant would make the forensic record lie, and
 * dropping the event would lose the one an operator most wants to see. So the
 * column becomes nullable and the NULL is meaningful: "not yet in a tenant
 * context".
 *
 * This also exercises the migration chain beyond version 1.
 */
static const char *const MIGRATION_2[] = {
  "CREATE TABLE audit_event_mig2 (id TEXT PRIMARY KEY,"
  "  tenant_id TEXT, actor_id TEXT, session_id TEXT,"
  "  action TEXT NOT NULL, object_type TEXT, object_id TEXT,"
  "  outcome TEXT NOT NULL, source_addr TEXT, before_json TEXT,"
  "  after_json TEXT, txn_id TEXT, detail TEXT, created_at TEXT NOT NULL);"
  "INSERT INTO audit_event_mig2 SELECT id,tenant_id,actor_id,session_id,"
  "  action,object_type,object_id,outcome,source_addr,before_json,"
  "  after_json,txn_id,NULL,created_at FROM audit_event;",
  "DROP TABLE audit_event;",
  "ALTER TABLE audit_event_mig2 RENAME TO audit_event;",
  "CREATE INDEX audit_event_tenant_time ON audit_event(tenant_id, created_at);",
  "CREATE INDEX audit_event_object ON audit_event(object_type, object_id);",
  NULL
};

int sr_db_migrate(sr_db *db, char **err)
{
    int cur = sr_db_version(db);
    if (cur < 0) { set_err(err, "cannot read user_version"); return -1; }

    if (cur < 1) {
        if (sr_db_exec(db, "BEGIN IMMEDIATE;", err) < 0) return -1;
        for (size_t i = 0; MIGRATION_1[i]; i++) {
            if (sr_db_exec(db, MIGRATION_1[i], err) < 0) {
                char *m = *err;
                char buf[SR_MAX_TEXT];
                snprintf(buf, sizeof buf, "migration 1, statement %zu: %s",
                         i + 1, m ? m : "?");
                free(m);
                if (err) *err = sr_xstrdup(buf);
                sr_db_rollback(db);
                return -1;
            }
        }
        sqlite3_stmt *st = NULL;
        if (sr_db_prepare(db,
                "INSERT INTO schema_migration(version,name,checksum,applied_at)"
                " VALUES(1,'base',?,datetime('now'));", &st, err) < 0) {
            sr_db_rollback(db); return -1;
        }
        sqlite3_bind_text(st, 1, "base", -1, SQLITE_STATIC);
        if (sqlite3_step(st) != SQLITE_DONE) {
            set_err(err, "%s", sqlite3_errmsg(db->h));
            sqlite3_finalize(st); sr_db_rollback(db); return -1;
        }
        sqlite3_finalize(st);
        if (sr_db_exec(db, "PRAGMA user_version=1;", err) < 0) { sr_db_rollback(db); return -1; }
        if (sr_db_exec(db, "COMMIT;", err) < 0) { sr_db_rollback(db); return -1; }
        sr_log(SR_LOG_INFO, "applied migration 1 (base schema)");
        cur = 1;
    }

    if (cur < 2) {
        if (sr_db_exec(db, "BEGIN IMMEDIATE;", err) < 0) return -1;
        for (size_t i = 0; MIGRATION_2[i]; i++) {
            if (sr_db_exec(db, MIGRATION_2[i], err) < 0) {
                char *m = *err;
                char buf[SR_MAX_TEXT];
                snprintf(buf, sizeof buf, "migration 2, statement %zu: %s",
                         i + 1, m ? m : "?");
                free(m);
                if (err) *err = sr_xstrdup(buf);
                sr_db_rollback(db);
                return -1;
            }
        }
        sqlite3_stmt *st2 = NULL;
        if (sr_db_prepare(db,
                "INSERT INTO schema_migration(version,name,checksum,applied_at)"
                " VALUES(2,'audit_nullable_tenant','m2',datetime('now'));",
                &st2, err) < 0) { sr_db_rollback(db); return -1; }
        sqlite3_step(st2);
        sqlite3_finalize(st2);
        if (sr_db_exec(db, "PRAGMA user_version=2;", err) < 0) { sr_db_rollback(db); return -1; }
        if (sr_db_exec(db, "COMMIT;", err) < 0) { sr_db_rollback(db); return -1; }
        sr_log(SR_LOG_INFO, "applied migration 2 (audit_event tenant_id nullable)");
    }
    return 0;
}

/* ------------------------------------------------------ state helpers */

static void now_ts(char *out, size_t n)
{
    time_t t = time(NULL);
    struct tm tm;
    gmtime_r(&t, &tm);
    strftime(out, n, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

int sr_state_put(sr_db *db, const char *tenant_id, const char *object_type,
                 const char *object_id, const char *desired_json,
                 const char *actor_id, char **err)
{
    char ts[32]; now_ts(ts, sizeof ts);
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO desired_state(object_type,object_id,tenant_id,desired_json,"
        "spec_revision,updated_by,updated_at) VALUES(?,?,?,?,1,?,?) "
        "ON CONFLICT(object_type,object_id) DO UPDATE SET "
        "desired_json=excluded.desired_json,"
        "spec_revision=desired_state.spec_revision+1,"
        "updated_by=excluded.updated_by, updated_at=excluded.updated_at;",
        &st, err) < 0) return -1;

    sqlite3_bind_text(st, 1, object_type, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, object_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, desired_json, -1, SQLITE_STATIC);
    if (actor_id) sqlite3_bind_text(st, 5, actor_id, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 5);
    sqlite3_bind_text(st, 6, ts, -1, SQLITE_STATIC);

    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    if (rc != SQLITE_DONE) { set_err(err, "%s", sqlite3_errmsg(db->h)); return -1; }
    return 0;
}

int sr_observed_put(sr_db *db, const char *tenant_id, const char *object_type,
                    const char *object_id, const char *health,
                    const char *source, const char *observed_json,
                    const char *detail)
{
    char ts[32]; now_ts(ts, sizeof ts);
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO observed_state(object_type,object_id,tenant_id,observed_json,"
        "health,source,observed_at,detail) VALUES(?,?,?,?,?,?,?,?) "
        "ON CONFLICT(object_type,object_id) DO UPDATE SET "
        "observed_json=excluded.observed_json, health=excluded.health,"
        "source=excluded.source, observed_at=excluded.observed_at,"
        "detail=excluded.detail;", &st, NULL) < 0) return -1;

    sqlite3_bind_text(st, 1, object_type, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, object_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, observed_json ? observed_json : "{}", -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 5, health, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 6, source, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 7, ts, -1, SQLITE_STATIC);
    if (detail) sqlite3_bind_text(st, 8, detail, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 8);

    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    return rc == SQLITE_DONE ? 0 : -1;
}

int sr_state_get(sr_db *db, const char *tenant_id, const char *object_type,
                 const char *object_id, char **out_json)
{
    sqlite3_stmt *st = NULL;
    *out_json = NULL;
    if (sr_db_prepare(db,
        "SELECT desired_json FROM desired_state "
        "WHERE tenant_id=? AND object_type=? AND object_id=?;",
        &st, NULL) < 0) return -1;
    sqlite3_bind_text(st, 1, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, object_type, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, object_id, -1, SQLITE_STATIC);
    int rc = 0;
    if (sqlite3_step(st) == SQLITE_ROW) {
        const unsigned char *t = sqlite3_column_text(st, 0);
        if (t) *out_json = xstrdup_or_null((const char *)t);
    }
    sqlite3_finalize(st);
    return rc;
}
