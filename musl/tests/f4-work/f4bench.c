#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
double nearbyint(double); float nearbyintf(float);
#define N 4096
static double dc[N]; static float fc[N];
static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}
static uint64_t bitsd(double x){uint64_t b;memcpy(&b,&x,8);return b;}
static uint64_t bitsf(float x){uint32_t b;memcpy(&b,&x,4);return b;}
static void gen(void){
	xst=0x123456789abcdefULL;
	for(int i=0;i<N;i++){
		uint64_t r=rnd64(); uint64_t b; int c=i%20;
		if(c<14) b=(r&0x8000000000000000ULL)|(((r>>11)%0x7FD+1)<<52)|((r>>5)&0xFFFFFFFFFFFFULL);
		else if(c<16) b=(r&0x8000000000000000ULL)|(((r>>18)%201)<<52);
		else if(c<18) b=(r&0x8000000000000000ULL)|0x3FF0000000000000ULL|(((r>>11)&1)<<51);
		else if(c<19) b=(r&1)?0:0x8000000000000000ULL;
		else b=(r&0x8000000000000000ULL)|((r>>11)&0xFFFFFFFFFFFFULL)|1ULL;
		memcpy(&dc[i],&b,8);
		uint32_t r2=(uint32_t)(r>>13); uint32_t bf;
		if(c<14) bf=(r2&0x80000000U)|((((r2>>9)%0xFD)+1)<<23)|((r2>>4)&0x7FFFFFU);
		else if(c<16) bf=(r2&0x80000000U)|(((r2>>16)%201)<<23);
		else if(c<18){ uint32_t bit=((r2>>9)&1U)<<22; bf=(r2&0x80000000U)|0x3F800000U|bit; }
		else if(c<19) bf=(r2&1)?0:0x80000000U;
		else bf=(r2&0x80000000U)|((r2>>9)&0x7FFFFFU)|1U;
		memcpy(&fc[i],&bf,4);
	}
}
static double tnow(void){struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);return ts.tv_sec+ts.tv_nsec*1e-9;}
static volatile uint64_t sink;
#define BENCHD(name,fn,arr,n) do{ \
	double t0=tnow(); uint64_t acc=0; \
	for(int r=0;r<REP;r++) for(int i=0;i<n;i++){double v=fn(arr[i]); acc^=bitsd(v)+0x9e3779b97f4a7c15ULL+(acc<<6)+(acc>>2);} \
	double t1=tnow(); sink=acc; \
	printf("%-12s %8.3f ns/call chk=%016lx\n",name,(t1-t0)/((double)REP*(n))*1e9,acc); \
}while(0)
#define BENCHF(name,fn,arr,n) do{ \
	double t0=tnow(); uint64_t acc=0; \
	for(int r=0;r<REP;r++) for(int i=0;i<n;i++){float v=fn(arr[i]); acc^=bitsf(v)+0x9e3779b97f4a7c15ULL+(acc<<6)+(acc>>2);} \
	double t1=tnow(); sink=acc; \
	printf("%-12s %8.3f ns/call chk=%016lx\n",name,(t1-t0)/((double)REP*(n))*1e9,acc); \
}while(0)
#define REP 200
static double d_frac[2048], d_big[1024], d_int[1024];
static float f_frac[2048], f_big[1024], f_int[1024];
static void split(void){
	int iF=0,iB=0,iI=0;
	for(int i=0;i<N;i++){
		uint64_t b; memcpy(&b,&dc[i],8);
		int e=(int)((b>>52)&0x7ff);
		if(e>=0x433&&e<0x7ff){if(iB<1024)d_big[iB++]=dc[i];}
		else if(e<0x3ff+52&&e>=0x3ff){if((b&0xFFFFFFFFFFFFFULL)==0){if(iI<1024)d_int[iI++]=dc[i];}else if(iF<2048)d_frac[iF++]=dc[i];}
		else if(e<0x3ff){if(iF<2048)d_frac[iF++]=dc[i];}
	}
	while(iF<2048)d_frac[iF++]=0.5; while(iB<1024)d_big[iB++]=1e16; while(iI<1024)d_int[iI++]=2.0;
	int jF=0,jB=0,jI=0;
	for(int i=0;i<N;i++){
		uint32_t b; memcpy(&b,&fc[i],4);
		int e=(int)((b>>23)&0xff);
		if(e>=0x96&&e<0xff){if(jB<1024)f_big[jB++]=fc[i];}
		else if(e<0x7f+23&&e>=0x7f){if((b&0x7FFFFFU)==0){if(jI<1024)f_int[jI++]=fc[i];}else if(jF<2048)f_frac[jF++]=fc[i];}
		else if(e<0x7f){if(jF<2048)f_frac[jF++]=fc[i];}
	}
	while(jF<2048)f_frac[jF++]=0.5f; while(jB<1024)f_big[jB++]=1e8f; while(jI<1024)f_int[jI++]=2.0f;
}
int main(void){
	gen(); split();
	{double w=0; for(int i=0;i<N;i++) w+=nearbyint(dc[i]); sink=(uint64_t)w;}
	printf("== fractional ==\n");
	BENCHD("nearbyint",nearbyint,d_frac,2048); BENCHF("nearbyintf",nearbyintf,f_frac,2048);
	printf("== big ==\n");
	BENCHD("nearbyint",nearbyint,d_big,1024); BENCHF("nearbyintf",nearbyintf,f_big,1024);
	printf("== integral ==\n");
	BENCHD("nearbyint",nearbyint,d_int,1024); BENCHF("nearbyintf",nearbyintf,f_int,1024);
	return 0;
}
