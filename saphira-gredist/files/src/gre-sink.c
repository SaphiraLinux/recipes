/* Saphira Linux (c) 2026 - MIT Licensed
 * gre-sink - test backend that counts GRE packets
 */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include "gredist.h"

static volatile int quit=0;
static void h(int s){ (void)s; quit=1; }

int main(int argc, char *argv[]){
    const char *bind_ip=NULL;
    const char *out_file=NULL;
    for(int i=1;i<argc;i++){
        if(strcmp(argv[i],"-b")==0 && i+1<argc) bind_ip=argv[++i];
        else if(strcmp(argv[i],"-o")==0 && i+1<argc) out_file=argv[++i];
        else { fprintf(stderr,"Usage: %s -b <bind-ip> [-o <output>]\n",argv[0]); return 1; }
    }
    if(!bind_ip){ fprintf(stderr,"need -b\n"); return 1; }
    struct in_addr a4; struct in6_addr a6;
    int family=0;
    struct sockaddr_storage bss; socklen_t blen=0;
    if(inet_pton(AF_INET,bind_ip,&a4)==1){ family=AF_INET; struct sockaddr_in *s=(struct sockaddr_in*)&bss; memset(s,0,sizeof(*s)); s->sin_family=AF_INET; s->sin_addr=a4; blen=sizeof(*s); }
    else if(inet_pton(AF_INET6,bind_ip,&a6)==1){ family=AF_INET6; struct sockaddr_in6 *s6=(struct sockaddr_in6*)&bss; memset(s6,0,sizeof(*s6)); s6->sin6_family=AF_INET6; memcpy(&s6->sin6_addr,&a6,16); blen=sizeof(*s6); }
    else { fprintf(stderr,"invalid ip %s\n",bind_ip); return 1; }

    int fd4=-1, fd6=-1;
    fd4=socket(AF_INET,SOCK_RAW,IPPROTO_GRE);
    fd6=socket(AF_INET6,SOCK_RAW,IPPROTO_GRE);
    if(fd4<0 && fd6<0){ perror("socket"); return 1; }
    if(fd4>=0){
        if(family==AF_INET){
            if(bind(fd4,(struct sockaddr*)&bss,blen)!=0) perror("bind v4");
        }
        int one=1; setsockopt(fd4,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    }
    if(fd6>=0){
        if(family==AF_INET6){
            if(bind(fd6,(struct sockaddr*)&bss,blen)!=0) perror("bind v6");
        }
        int one=1; setsockopt(fd6,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    }

    signal(SIGINT,h); signal(SIGTERM,h);
    uint64_t cnt=0, malformed=0;
    uint8_t buf[65536];
    struct pollfd pf[2]; int n=0;
    if(fd4>=0){ pf[n].fd=fd4; pf[n].events=POLLIN; n++; }
    if(fd6>=0){ pf[n].fd=fd6; pf[n].events=POLLIN; n++; }

    FILE *out = stdout;
    if(out_file){ out=fopen(out_file,"w"); if(!out){ perror("fopen"); return 1; } setvbuf(out,NULL,_IOLBF,0); }

    fprintf(out,"# gre-sink %s listening family=%s\n", bind_ip, family==AF_INET?"v4":"v6");
    fflush(out);

    while(!quit){
        int pr=poll(pf,n,1000);
        if(pr<0){ if(errno==EINTR) continue; perror("poll"); break; }
        for(int i=0;i<n;i++){
            if(!(pf[i].revents&POLLIN)) continue;
            struct sockaddr_storage src; socklen_t sl=sizeof(src);
            ssize_t m=recvfrom(pf[i].fd,buf,sizeof(buf),0,(struct sockaddr*)&src,&sl);
            if(m<0){ if(errno==EAGAIN) continue; continue; }
            cnt++;
            int ofam=0; size_t olen=0; uint8_t sbytes[16]; size_t slen=0; uint8_t dbytes[16]; size_t dlen=0;
            int po=parse_outer(buf,(size_t)m,&ofam,&olen,sbytes,&slen,dbytes,&dlen);
            struct gre_info gi; int gr=-1;
            int fallback=0;
            if(po!=0){
                /* fallback for IPv6 headerless */
                if(pf[i].fd==fd6 && src.ss_family==AF_INET6 && (size_t)m >=4){
                    fallback=1; ofam=AF_INET6; olen=0;
                    slen=16; memcpy(sbytes,&((struct sockaddr_in6*)&src)->sin6_addr,16);
                    dlen=16; memcpy(dbytes,&((struct sockaddr_in6*)&bss)->sin6_addr,16);
                    po=0;
                }
            }
            if(po==0) gr=gre_parse(buf,(size_t)m,olen,&gi);
            char sstr[INET6_ADDRSTRLEN]={0}, dstr[INET6_ADDRSTRLEN]={0};
            if(slen==4) inet_ntop(AF_INET,sbytes,sstr,sizeof(sstr));
            else if(slen==16) inet_ntop(AF_INET6,sbytes,sstr,sizeof(sstr));
            else snprintf(sstr,sizeof(sstr),"unknown");
            if(dlen==4) inet_ntop(AF_INET,dbytes,dstr,sizeof(dstr));
            else if(dlen==16) inet_ntop(AF_INET6,dbytes,dstr,sizeof(dstr));
            else snprintf(dstr,sizeof(dstr),"unknown");

            if(po!=0 || gr!=0){
                malformed++;
                fprintf(out,"malformed outer=%d gre=%d cnt=%lu fallback=%d\n",po,gr,(unsigned long)cnt,fallback);
                continue;
            }
            char keystr[32];
            if(gi.has_key) snprintf(keystr,sizeof(keystr),"0x%08x",gi.key);
            else snprintf(keystr,sizeof(keystr),"none");

            char src_ip[INET6_ADDRSTRLEN*2]={0};
            if(pf[i].fd==fd4){
                struct sockaddr_in *a=(struct sockaddr_in*)&src;
                inet_ntop(AF_INET,&a->sin_addr,src_ip,sizeof(src_ip));
            } else {
                struct sockaddr_in6 *a6p=(struct sockaddr_in6*)&src;
                inet_ntop(AF_INET6,&a6p->sin6_addr,src_ip,sizeof(src_ip));
            }

            fprintf(out,"pkt %lu src_outer=%s dst=%s gre_key=%s proto=0x%04x payload=%zu recv_src=%s\n",
                (unsigned long)cnt, sstr, dstr, keystr, ntohs(gi.proto), (size_t)m - olen - gi.hdr_len, src_ip);
            fflush(out);
        }
    }
    fprintf(out,"# exit cnt=%lu malformed=%lu\n",(unsigned long)cnt,(unsigned long)malformed);
    if(out!=stdout) fclose(out);
    if(fd4>=0) close(fd4);
    if(fd6>=0) close(fd6);
    return 0;
}
