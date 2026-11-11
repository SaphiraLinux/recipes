#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
size_t avx2_ascii_span(const unsigned char *s, size_t n);
static __attribute__((noinline)) size_t ref_span(const unsigned char *s, size_t n){size_t c=0;while(n-->0&&!(*s&0x80)){s++;c++;}return c;}
#define N (256*1024)
static unsigned char asc[N], mix[N];
static double tnow(void){struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);return ts.tv_sec+ts.tv_nsec*1e-9;}
static volatile size_t sink;
#define REP 500
int main(void){
	memset(asc,0x41,N);
	for(int i=0;i<N;i++) asc[i]=0x20+(i%0x5F);
	uint64_t x=0x123456789abcdefULL;
	for(int i=0;i<N;i++){x^=x<<13;x^=x>>7;x^=x<<17;
		int c=i%100; /* 90% ascii, 10% 2-byte */
		if(c<90) mix[i]=0x20+(x%0x5F);
		else if((i%2)==0){mix[i]=0xC3; if(i+1<N)mix[++i]=0xA9; }
		else mix[i]=0x41;}
	for(int t=0;t<2;t++){
		{double t0=tnow();size_t a=0;for(int r=0;r<REP;r++)a+=ref_span(asc,N);double t1=tnow();sink=a;
		printf("ascii  scalar %8.3f ns/call chk=%zu\n",(t1-t0)/REP*1e9,a);}
		{double t0=tnow();size_t a=0;for(int r=0;r<REP;r++)a+=avx2_ascii_span(asc,N);double t1=tnow();sink=a;
		printf("ascii  avx2   %8.3f ns/call chk=%zu\n",(t1-t0)/REP*1e9,a);}
		{double t0=tnow();size_t a=0;for(int r=0;r<REP;r++)a+=ref_span(mix,N);double t1=tnow();sink=a;
		printf("mixed  scalar %8.3f ns/call chk=%zu\n",(t1-t0)/REP*1e9,a);}
		{double t0=tnow();size_t a=0;for(int r=0;r<REP;r++)a+=avx2_ascii_span(mix,N);double t1=tnow();sink=a;
		printf("mixed  avx2   %8.3f ns/call chk=%zu\n",(t1-t0)/REP*1e9,a);}
	}
	return 0;
}
