/* sr_db.h -- core-owned SQLite access.
 *
 * THE CORE IS THE ONLY WRITER. TUI, CLI, drones, modules and observers all
 * submit through the API and are applied here (D1 3.2, D4 1). Nothing else
 * opens this database; the file permissions are a backstop, not the
 * mechanism.
 */

#ifndef SR_DB_H
#define SR_DB_H

#include <sqlite3.h>
#include "sr.h"

typedef struct sr_db sr_db;

/* Open (creating if needed) and run migrations. WAL + busy_timeout are set
 * here because the *core* is concurrent: API handling, observers,
 * transaction processing (D4 1). This is not permission for clients to write. */
int  sr_db_open(const char *path, sr_db **out);
void sr_db_close(sr_db *db);
sqlite3 *sr_db_handle(sr_db *db);

/* Apply pending migrations (PRAGMA user_version chain, D4 3). */
int sr_db_migrate(sr_db *db, char **err);

/* Thin helpers. All of these run as the core. */
int sr_db_exec(sr_db *db, const char *sql, char **err);
int sr_db_prepare(sr_db *db, const char *sql, sqlite3_stmt **st, char **err);

/* Current schema version, or -1. */
int sr_db_version(sr_db *db);

/* Single-text-column query into a malloc'd string (or NULL).
 *
 * CAUTION: this does NOT bind parameters. Passing a SQL string containing
 * '?' here will read an unbound column as NULL, which looks like "no such
 * row" and turns into a silent wrong answer. Use a prepared statement with
 * sqlite3_bind_*() whenever the query has parameters. */
int sr_db_query_text(sr_db *db, const char *sql, char **out);

/* Transaction helpers for the core's own multi-statement writes. */
int sr_db_begin(sr_db *db, char **err);
int sr_db_commit(sr_db *db, char **err);
int sr_db_rollback(sr_db *db);

/* Desired/observed state (D4 10, D7). */
int sr_state_put(sr_db *db, const char *tenant_id, const char *object_type,
                 const char *object_id, const char *desired_json,
                 const char *actor_id, char **err);
int sr_observed_put(sr_db *db, const char *tenant_id, const char *object_type,
                    const char *object_id, const char *health,
                    const char *source, const char *observed_json,
                    const char *detail);
int sr_state_get(sr_db *db, const char *tenant_id, const char *object_type,
                 const char *object_id, char **out_json);

#endif /* SR_DB_H */
