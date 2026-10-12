#include "sr_db.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
int main(void){
    sr_db *db=NULL; char *err=NULL;
    unlink("/tmp/sr_t.db"); unlink("/tmp/sr_t.db-wal"); unlink("/tmp/sr_t.db-shm");
    if (sr_db_open("/tmp/sr_t.db",&db)<0){ puts("FAIL open"); return 1; }
    if (sr_db_migrate(db,&err)<0){ printf("FAIL migrate: %s\n",err?err:"?"); return 1; }
    printf("  user_version = %d\n", sr_db_version(db));
    sqlite3_stmt *st;
    sr_db_prepare(db,"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",&st,NULL);
    printf("  tables:"); int n=0;
    while(sqlite3_step(st)==SQLITE_ROW){ printf(" %s",sqlite3_column_text(st,0)); n++; }
    printf("\n  (%d tables)\n",n); sqlite3_finalize(st);
    sr_db_prepare(db,"SELECT COUNT(*) FROM capability",&st,NULL);
    sqlite3_step(st); printf("  capabilities seeded: %d\n",sqlite3_column_int(st,0)); sqlite3_finalize(st);
    /* the CHECK must reject a bogus capability state */
    sr_db_exec(db,"INSERT INTO host(id,tenant_id,hostname) VALUES('h1','t1','n1')",&err);
    int rc=sqlite3_exec(sr_db_handle(db),
        "INSERT INTO host_capability(host_id,capability,state,checked_at) VALUES('h1','x','bogus','now')",NULL,NULL,NULL);
    printf("  bogus state rejected by CHECK: %s\n", rc==SQLITE_CONSTRAINT?"yes":"NO");
    /* migration is idempotent */
    if (sr_db_migrate(db,&err)<0){ puts("  FAIL re-migrate"); return 1; }
    printf("  re-migrate idempotent: yes (version %d)\n", sr_db_version(db));
    sr_db_close(db); return 0;
}
