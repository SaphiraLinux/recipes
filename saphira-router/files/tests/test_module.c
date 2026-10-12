#include "sr_db.h"
#include "sr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern int sr_module_load_all(sr_db*, const char*, const char*, const char*);
extern int sr_module_count(void);
extern char *sr_module_registry_json(sr_db*);
static void ok(const char*w,int c){ printf("  %-56s %s\n",w,c?"PASS":"**FAIL**"); if(!c) exit(1); }
static const char*state_of(sr_db*db,const char*name){
    char q[256]; snprintf(q,sizeof q,"SELECT state FROM module_registry WHERE module_name='%s';",name);
    static char b[64]; b[0]=0; char*r=NULL; sr_db_query_text(db,q,&r);
    if(r){ snprintf(b,sizeof b,"%s",r); free(r);} return b;
}
static int has_event(sr_db*db,const char*action,const char*outcome,const char*obj){
    char *n=NULL;
    char sql[256];
    snprintf(sql,sizeof sql,
        "SELECT COUNT(*) FROM audit_event WHERE action='%s' AND outcome='%s' "
        "AND object_id='%s';",action,outcome,obj);
    sr_db_query_text(db,sql,&n);
    int r = n?atoi(n):-1; free(n); return r;
}

static const char*diag_of(sr_db*db,const char*name){
    char q[256]; snprintf(q,sizeof q,"SELECT diagnostic FROM module_registry WHERE module_name='%s';",name);
    static char b[256]; b[0]=0; char*r=NULL; sr_db_query_text(db,q,&r);
    if(r){ snprintf(b,sizeof b,"%s",r); free(r);} return b;
}
int main(int argc,char**argv){
    const char *dir = argc>1?argv[1]:"build";
    unlink("/tmp/sr_m.db"); unlink("/tmp/sr_m.db-wal"); unlink("/tmp/sr_m.db-shm");
    sr_db *db=NULL; char *err=NULL;
    sr_db_open("/tmp/sr_m.db",&db); sr_db_migrate(db,&err);
    sr_db_exec(db,"INSERT INTO tenant(id,slug,name,created_at,updated_at)"
                 " VALUES('t1','t','T',datetime('now'),datetime('now'))",&err);
    int n=sr_module_load_all(db,dir,"actor","t1");
    printf("  modules discovered: %d\n",n);
    ok("exactly one module loaded (badabi refused)", n==1);
    ok("fixture recorded 'loaded'",  strcmp(state_of(db,"fixture"),"loaded")==0);
    ok("badabi recorded 'incompatible'", strcmp(state_of(db,"badabi"),"incompatible")==0);
    printf("  badabi diagnostic: %s\n", diag_of(db,"badabi"));
    ok("refusal names the ABI mismatch",
       strstr(diag_of(db,"badabi"),"ABI")!=NULL && strstr(diag_of(db,"badabi"),"100")!=NULL);
    ok("refusal is NOT optimistically loaded",
       strcmp(state_of(db,"badabi"),"loaded")!=0);
    char *j=sr_module_registry_json(db);
    printf("  registry json: %s\n",j);
    ok("registry json lists fixture as loaded", strstr(j,"\"fixture\"")!=NULL);
    ok("registry json carries the badabi diagnostic", strstr(j,"not supported")!=NULL);
    free(j);
    /* core usable with NO modules at all */
    int n2=sr_module_load_all(db,"/nonexistent-moddir","actor","t1");
      /* --- the refusal is AUDITED with its reason, in the right column ---
       * sr_audit's 9th and 10th parameters are adjacent const char *, so a
       * swapped pair compiles with no warning. Module refusals and capability
       * probes both did exactly that: the reason went into source_addr and
       * detail came out NULL. The trail therefore recorded a refused module
       * with no explanation, and a "source address" reading
       * "incompatible: module ABI 100 is not supported".
       *
       * A refusal is precisely the event whose reason an operator will later
       * need and cannot reconstruct, so this asserts column placement, not
       * merely that a row exists. */
      {
          char *d=NULL, *sa=NULL, *n=NULL;
          sr_db_query_text(db,
              "SELECT COALESCE(detail,'') FROM audit_event "
              "WHERE action='module.refuse' AND object_id='badabi' "
              "ORDER BY rowid DESC LIMIT 1;", &d);
          sr_db_query_text(db,
              "SELECT COALESCE(source_addr,'') FROM audit_event "
              "WHERE action='module.refuse' AND object_id='badabi' "
              "ORDER BY rowid DESC LIMIT 1;", &sa);
          ok("the refusal is audited as denied", has_event(db,"module.refuse","denied","badabi")==1);
          ok("the audit detail carries the refusal reason", d && *d && strstr(d,"ABI")!=NULL);
          ok("the audit detail names the module version and the supported ABI",
             d && strstr(d,"100") && strstr(d,"1"));
          ok("the reason is NOT misfiled into source_addr", sa && *sa=='\0');
          printf("  audit detail: %s\n", d ? d : "(empty)");
          sr_db_query_text(db,
              "SELECT COUNT(*) FROM audit_event WHERE action='module.refuse' "
              "AND (detail IS NULL OR detail='');", &n);
          ok("no module refusal anywhere has an empty detail", n && atoi(n)==0);
          free(d); free(sa); free(n);
      }

    ok("absent module dir loads nothing, without erroring", n2==0);
    ok("already-loaded modules are not lost", sr_module_count()==n);
    puts("  ALL PASS");
    return 0;
}
