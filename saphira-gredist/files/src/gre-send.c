/* Saphira Linux (c) 2026 - MIT Licensed
 * gre-send - test tool to send GRE packet with/without key
 */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <errno.h>
#include <getopt.h>

static uint16_t ip_csum(const void *buf, size_t len){
    uint32_t sum=0;
    const uint16_t *p=buf;
    while(len>1){ sum+=*p++; len-=2; }
    if(len) sum+= *(uint8_t*)p;
    while(sum>>16) sum=(sum&0xFFFF)+(sum>>16);
    return ~sum;
}

int main(int argc,char *argv[]){
    const char *frontend=NULL;
    const char *src=NULL;
    const char *key_str=NULL;
    const char *payload_str="hello";
    int use_seq=0;
    int use_csum=0;
    int malformed=0; /* 1=truncated, 2=oversized etc */
    int family=AF_INET;

    static struct option opts[]={
        {"frontend",required_argument,0,'f'},
        {"src",required_argument,0,'s'},
        {"key",required_argument,0,'k'},
        {"payload",required_argument,0,'p'},
        {"csum",no_argument,0,'c'},
        {"seq",no_argument,0,'q'},
        {"malformed",required_argument,0,'m'},
        {"family",required_argument,0,'F'},
        {"help",no_argument,0,'h'},
        {0,0,0,0}
    };
    int c;
    while((c=getopt_long(argc,argv,"f:s:k:p:cqm:F:h",opts,NULL))!=-1){
        switch(c){
            case 'f': frontend=optarg; break;
            case 's': src=optarg; break;
            case 'k': key_str=optarg; break;
            case 'p': payload_str=optarg; break;
            case 'c': use_csum=1; break;
            case 'q': use_seq=1; break;
            case 'm': malformed=atoi(optarg); break;
            case 'F': family=(strcmp(optarg,"6")==0?AF_INET6:AF_INET); break;
            case 'h': printf("Usage: gre-send -f <frontend> [-s <src>] [-k <key>] [-p payload] [--csum] [--seq] [-m 1] [-F 4|6]\n"); return 0;
        }
    }
    if(!frontend){ fprintf(stderr,"need -f\n"); return 1; }

    /* determine frontend family if not forced */
    struct in_addr fa4; struct in6_addr fa6;
    int front_fam=AF_INET;
    if(inet_pton(AF_INET,frontend,&fa4)==1) front_fam=AF_INET;
    else if(inet_pton(AF_INET6,frontend,&fa6)==1) front_fam=AF_INET6;
    else { fprintf(stderr,"invalid frontend %s\n",frontend); return 1; }
    if(family!=front_fam){
        /* malformed family mismatch test? just use requested */
    }

    uint32_t key=0; int has_key=0;
    if(key_str){ key=(uint32_t)strtoul(key_str,NULL,0); has_key=1; }

    size_t payload_len=strlen(payload_str);
    /* GRE header */
    uint8_t gre[16]; size_t gre_len=4;
    uint16_t flags=0;
    if(use_csum) flags|=0x8000;
    if(has_key) flags|=0x2000;
    if(use_seq) flags|=0x1000;
    gre[0]=(flags>>8)&0xFF; gre[1]=flags&0xFF;
    gre[2]=0x08; gre[3]=0x00; /* proto IPv4 */
    size_t off=4;
    if(use_csum){ memset(gre+off,0,4); off+=4; }
    if(has_key){ gre[off++]=(key>>24)&0xFF; gre[off++]=(key>>16)&0xFF; gre[off++]=(key>>8)&0xFF; gre[off++]=(key>>0)&0xFF; }
    if(use_seq){ uint32_t seq=0x12345678; gre[off++]=(seq>>24)&0xFF; gre[off++]=(seq>>16)&0xFF; gre[off++]=(seq>>8)&0xFF; gre[off++]=(seq>>0)&0xFF; }
    gre_len=off;

    if(malformed==1){
        /* truncated: claim key but not include bytes -> send only base header 4 bytes */
        gre[0]=0x20; gre[1]=0x00; /* KEY set */
        gre_len=4;
        payload_len=0; /* no payload, so GRE claims 8 bytes but we send 4 */
        has_key=0;
    } else if(malformed==2){
        /* version non-zero */
        gre[0]=0x00; gre[1]=0x01; /* version 1 */
    } else if(malformed==3){
        /* routing bit */
        gre[0]=0x40; gre[1]=0x00;
    } else if(malformed==4){
        /* oversized: huge payload */
        payload_len=9000;
    } else if(malformed==5){
        /* фрагмент: will set frag_off later */
        payload_len=strlen(payload_str);
    }

    if(front_fam==AF_INET){
        if(src){
            /* spoofed src via HDRINCL */
            int fd=socket(AF_INET,SOCK_RAW,IPPROTO_RAW);
            if(fd<0){ perror("socket"); return 1; }
            int one=1; if(setsockopt(fd,IPPROTO_IP,IP_HDRINCL,&one,sizeof(one))<0){ perror("hdrincl"); return 1; }
            uint8_t pkt[65536];
            struct iphdr *iph=(struct iphdr*)pkt;
            memset(iph,0,sizeof(*iph));
            iph->version=4; iph->ihl=5; iph->tos=0;
            size_t iplen=20+gre_len+payload_len;
            iph->tot_len=htons(iplen);
            iph->id=htons(0x1234);
            iph->frag_off=0;
            if(malformed==5) iph->frag_off=htons(0x2000); /* MF */
            iph->ttl=64;
            iph->protocol=47;
            if(inet_pton(AF_INET,src,&iph->saddr)!=1){ fprintf(stderr,"invalid src\n"); return 1; }
            if(inet_pton(AF_INET,frontend,&iph->daddr)!=1){ fprintf(stderr,"bad frontend\n"); return 1; }
            iph->check=0;
            iph->check=ip_csum(iph,20);
            memcpy(pkt+20,gre,gre_len);
            if(malformed!=1) memcpy(pkt+20+gre_len,payload_str,payload_len > 100 ? 100 : payload_len);
            if(malformed==4) memset(pkt+20+gre_len,'A',payload_len);
            struct sockaddr_in dst; memset(&dst,0,sizeof(dst));
            dst.sin_family=AF_INET;
            dst.sin_addr.s_addr=iph->daddr;
            ssize_t n=sendto(fd,pkt,iplen,0,(struct sockaddr*)&dst,sizeof(dst));
            if(n<0){ perror("sendto"); return 1; }
            printf("sent %zd bytes to %s key=%s spoof=%s\n",n,frontend, has_key?key_str:"none", src);
            close(fd);
        } else {
            /* kernel selects src (client interface IP) */
            int fd=socket(AF_INET,SOCK_RAW,IPPROTO_GRE);
            if(fd<0){ perror("socket GRE"); return 1; }
            struct sockaddr_in dst; memset(&dst,0,sizeof(dst));
            dst.sin_family=AF_INET;
            if(inet_pton(AF_INET,frontend,&dst.sin_addr)!=1){ fprintf(stderr,"bad frontend\n"); return 1; }
            uint8_t out[65536];
            memcpy(out,gre,gre_len);
            size_t pl = payload_len > 100 ? 100 : payload_len;
            if(malformed==4){ memset(out+gre_len,'A',payload_len); pl=payload_len; }
            else memcpy(out+gre_len,payload_str,pl);
            ssize_t n=sendto(fd,out,gre_len+pl,0,(struct sockaddr*)&dst,sizeof(dst));
            if(n<0){ perror("sendto"); return 1; }
            printf("sent %zd bytes to %s key=%s (auto src)\n",n,frontend, has_key?key_str:"none");
            close(fd);
        }
    } else {
        /* IPv6 - use SOCK_RAW IPPROTO_GRE and let kernel add header, cannot spoof src easily via HDRINCL (needs IPV6_HDRINCL which is less portable)
         * So we use raw GRE socket and sendto; src will be selected by kernel based on routing. For src testing we need to bind.
         */
        int fd=socket(AF_INET6,SOCK_RAW,IPPROTO_GRE);
        if(fd<0){ perror("socket6"); return 1; }
        if(src){
            struct sockaddr_in6 s6; memset(&s6,0,sizeof(s6));
            s6.sin6_family=AF_INET6;
            if(inet_pton(AF_INET6,src,&s6.sin6_addr)!=1){ fprintf(stderr,"bad src6\n"); return 1; }
            if(bind(fd,(struct sockaddr*)&s6,sizeof(s6))!=0) perror("bind");
        }
        struct sockaddr_in6 dst6; memset(&dst6,0,sizeof(dst6));
        dst6.sin6_family=AF_INET6;
        if(inet_pton(AF_INET6,frontend,&dst6.sin6_addr)!=1){ fprintf(stderr,"bad frontend6\n"); return 1; }
        uint8_t out[65536];
        memcpy(out,gre,gre_len);
        memcpy(out+gre_len,payload_str,payload_len);
        if(malformed==4) memset(out+gre_len,'A',payload_len);
        ssize_t n=sendto(fd,out,gre_len+payload_len,0,(struct sockaddr*)&dst6,sizeof(dst6));
        if(n<0){ perror("sendto6"); return 1; }
        printf("sent6 %zd to %s\n",n,frontend);
        close(fd);
    }
    return 0;
}
