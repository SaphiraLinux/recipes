#include "sr_db.h"
#include "sr_auth.h"
#include "sr_rbac.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static void ok(const char*w,int c){ printf("  %-52s %s\n", w, c?"PASS":"**FAIL**"); if(!c) exit(1); }
int main(void){
    unlink("/tmp/sr_a.db"); unlink("/tmp/sr_a.db-wal"); unlink("/tmp/sr_a.db-shm");
    sr_db *db=NULL; char *err=NULL;
    sr_db_open("/tmp/sr_a.db",&db); sr_db_migrate(db,&err);
    sr_db_exec(db,"INSERT INTO tenant(id,slug,name,created_at,updated_at)"
                  " VALUES('tA','tenanta','Tenant A',datetime('now'),datetime('now'))",&err);
    char *uid=NULL,*pw=NULL;
    ok("create user", sr_auth_create_user(db,"alice","correct horse",&uid,&err)==0);
    /* a user needs a tenant context to authenticate: no role == no context */
    char *early=NULL,*earlyt=NULL;
    ok("no role yet -> no tenant context -> denied",
       sr_auth_verify(db,"alice","correct horse",&early,&earlyt,&err)==SR_ERR_DENIED);
    char *prole=NULL; sr_rbac_create_role(db,"tA","viewer","v",&prole,&err);
    sr_rbac_assign(db,uid,prole,"tA",&err);
    /* argon2id, never plaintext */
    char *enc=NULL; sqlite3_stmt *st;
    sr_db_prepare(db,"SELECT password_hash,password_algo FROM app_user WHERE id=?",&st,NULL);
    sqlite3_bind_text(st,1,uid,-1,SQLITE_STATIC); sqlite3_step(st);
    enc=sr_xstrdup((const char*)sqlite3_column_text(st,0));
    static char algo[32]; snprintf(algo,sizeof algo,"%s",(const char*)sqlite3_column_text(st,1));
    sqlite3_finalize(st);
    printf("  algo=%s prefix=%.10s\n", algo, enc);
    ok("stored hash is argon2id PHC", strncmp(enc,"$argon2id$",10)==0);
    ok("plaintext NOT in stored hash", !strstr(enc,"correct"));
    /* verify */
    char *v1=NULL,*t1=NULL;
    ok("correct password verifies", sr_auth_verify(db,"alice","correct horse",&v1,&t1,&err)==SR_OK);
    char *v2=NULL,*t2=NULL;
    ok("wrong password denied",     sr_auth_verify(db,"alice","wrong",&v2,&t2,&err)==SR_ERR_DENIED);
    char *v3=NULL,*t3=NULL;
    ok("unknown user denied identically", sr_auth_verify(db,"nobody","x",&v3,&t3,&err)==SR_ERR_DENIED);
    /* sessions bound to (user,tenant) */
    char *tok=NULL,*sid=NULL;
    ok("session created", sr_auth_session_create(db,v1,t1,NULL,&tok,&sid,&err)==0);
    char *su=NULL,*stn=NULL,*ss=NULL;
    ok("session resolves to user+tenant", sr_auth_session_lookup(db,tok,&su,&stn,&ss)==0
        && su&&strcmp(su,v1)==0 && stn&&strcmp(stn,t1)==0);
    /* token must NOT be stored in the clear */
    char *th=NULL; sr_db_query_text(db,"SELECT token_hash FROM session",&th);
    printf("  stored token_hash len=%zu (token len=%zu)\n", strlen(th), strlen(tok));
    ok("session token NOT stored in clear", strcmp(th,tok)!=0);
    /* deny by default */
    char *rid=NULL;
    sr_rbac_create_role(db,"tA","operator","op",&rid,&err);
    sr_rbac_assign(db,v1,rid,"tA",&err);
    char *why=NULL;
    ok("deny-by-default: no capability granted yet",
       sr_rbac_authorize(db,v1,"tA","host.enroll",&why)==0 && why!=NULL);
    free(why); why=NULL;
    ok("grant unknown capability is refused",
       sr_rbac_grant(db,rid,"not.a.real.capability",&err)!=0);
    sr_rbac_grant(db,rid,"host.enroll",&err);
    why=NULL;
    ok("granted capability allowed",
       sr_rbac_authorize(db,v1,"tA","host.enroll",&why)==1);
    /* admin must not imply a FUTURE capability */
    char *arid=NULL; sr_rbac_create_role(db,"tA","admin","a",&arid,&err);
    sr_rbac_assign(db,v1,arid,"tA",&err);
    int before=sr_rbac_effective_count(db,v1,"tA");
    /* a new capability appears (as a new module would register) */
    sr_db_exec(db,"INSERT INTO capability(code,description) VALUES('udppdist.future','future')",&err);
    int after=sr_rbac_effective_count(db,v1,"tA");
    ok("new capability does NOT auto-join admin", before==after);
    why=NULL;
    ok("new capability denied until granted",
       sr_rbac_authorize(db,v1,"tA","udppdist.future",&why)==0);
    /* tenant isolation: role in tA must not authorize in tB */
    sr_db_exec(db,"INSERT INTO tenant(id,slug,name,created_at,updated_at)"
                  " VALUES('tB','tenantb','Tenant B',datetime('now'),datetime('now'))",&err);
    why=NULL;
    ok("cross-tenant: denied in tenant B", sr_rbac_authorize(db,v1,"tB","host.enroll",&why)==0);
    why=NULL;
    ok("cross-tenant: still allowed in tenant A", sr_rbac_authorize(db,v1,"tA","host.enroll",&why)==1);
    puts("  ALL PASS");
    return 0;
}
