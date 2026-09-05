/* Saphira Linux (c) 2026 - MIT Licensed
 * saphira-gredist config parser - simple frontend/backend lines
 */
#include "gredist.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <arpa/inet.h>
#include <errno.h>

static char *trim(char *s){
    char *e;
    while(*s && isspace((unsigned char)*s)) s++;
    if(*s=='\0') return s;
    e = s + strlen(s)-1;
    while(e> s && isspace((unsigned char)*e)){ *e='\0'; e--; }
    return s;
}

int load_config(const char *path, struct service *svc, const char *service_name){
    memset(svc,0,sizeof(*svc));
    if(service_name) snprintf(svc->name,sizeof(svc->name),"%s",service_name);
    FILE *f = fopen(path,"r");
    if(!f){
        fprintf(stderr,"gredist: cannot open %s: %s\n",path,strerror(errno));
        return -1;
    }
    char line[512];
    int lineno=0;
    int has_frontend=0;
    while(fgets(line,sizeof(line),f)){
        lineno++;
        line[strcspn(line,"\r\n")]='\0';
        char *t = trim(line);
        if(*t=='\0' || *t=='#' || *t==';') continue;
        char *eq = strchr(t,'=');
        if(!eq){
            fprintf(stderr,"gredist: %s:%d: invalid line (no '='): %s\n",path,lineno,t);
            fclose(f);
            return -1;
        }
        *eq='\0';
        char *k = trim(t);
        char *v = trim(eq+1);
        if(strcmp(k,"frontend")==0){
            if(has_frontend){
                fprintf(stderr,"gredist: %s:%d: duplicate frontend\n",path,lineno);
                fclose(f); return -1;
            }
            if(strlen(v)>=sizeof(svc->frontend_str)){
                fprintf(stderr,"gredist: %s:%d: frontend too long\n",path,lineno);
                fclose(f); return -1;
            }
            strncpy(svc->frontend_str,v,sizeof(svc->frontend_str)-1);
            /* detect family */
            struct in_addr a4;
            struct in6_addr a6;
            if(inet_pton(AF_INET,v,&a4)==1){
                svc->frontend_family=AF_INET;
                struct sockaddr_in *sin=(struct sockaddr_in*)&svc->frontend_ss;
                memset(sin,0,sizeof(*sin));
                sin->sin_family=AF_INET;
                sin->sin_addr=a4;
                svc->frontend_len=sizeof(*sin);
            } else if(inet_pton(AF_INET6,v,&a6)==1){
                svc->frontend_family=AF_INET6;
                struct sockaddr_in6 *sin6=(struct sockaddr_in6*)&svc->frontend_ss;
                memset(sin6,0,sizeof(*sin6));
                sin6->sin6_family=AF_INET6;
                memcpy(&sin6->sin6_addr,&a6,16);
                svc->frontend_len=sizeof(*sin6);
            } else {
                fprintf(stderr,"gredist: %s:%d: invalid frontend IP '%s'\n",path,lineno,v);
                fclose(f); return -1;
            }
            has_frontend=1;
        } else if(strcmp(k,"backend")==0){
            if(svc->nbackends >= MAX_BACKENDS){
                fprintf(stderr,"gredist: %s:%d: too many backends (max %d)\n",path,lineno,MAX_BACKENDS);
                fclose(f); return -1;
            }
            struct backend *b=&svc->backends[svc->nbackends];
            memset(b,0,sizeof(*b));
            strncpy(b->str,v,sizeof(b->str)-1);
            struct in_addr a4;
            struct in6_addr a6;
            if(inet_pton(AF_INET,v,&a4)==1){
                b->family=AF_INET;
                struct sockaddr_in *sin=(struct sockaddr_in*)&b->ss;
                memset(sin,0,sizeof(*sin));
                sin->sin_family=AF_INET;
                sin->sin_addr=a4;
                b->ss_len=sizeof(*sin);
            } else if(inet_pton(AF_INET6,v,&a6)==1){
                b->family=AF_INET6;
                struct sockaddr_in6 *sin6=(struct sockaddr_in6*)&b->ss;
                memset(sin6,0,sizeof(*sin6));
                sin6->sin6_family=AF_INET6;
                memcpy(&sin6->sin6_addr,&a6,16);
                b->ss_len=sizeof(*sin6);
            } else {
                fprintf(stderr,"gredist: %s:%d: invalid backend IP '%s'\n",path,lineno,v);
                fclose(f); return -1;
            }
            b->healthy=1;
            backend_compute_hash(b);
            svc->nbackends++;
        } else {
            fprintf(stderr,"gredist: %s:%d: unknown key '%s'\n",path,lineno,k);
            fclose(f); return -1;
        }
    }
    fclose(f);
    if(!has_frontend){
        fprintf(stderr,"gredist: %s: missing frontend=\n",path);
        return -1;
    }
    if(svc->nbackends==0){
        fprintf(stderr,"gredist: %s: no backends\n",path);
        return -1;
    }
    return 0;
}
