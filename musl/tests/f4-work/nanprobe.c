#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <pmmintrin.h>
double nearbyint(double); float nearbyintf(float);
static sigjmp_buf jb; static volatile int trapped;
static void onfpe(int s){(void)s; trapped=1; siglongjmp(jb,1);}
static void runt(const char *n, uint64_t b){
	double x; memcpy(&x,&b,8);
	unsigned m0=_mm_getcsr();
	_mm_setcsr((m0&~(0x3f|0x1f80))|0x1F00);
	trapped=0; volatile double s;
	if(sigsetjmp(jb,1)==0){ s=nearbyint(x); }
	printf("%s bits=%lx trap=%d r=%a\n",n,b,trapped,s);
	_mm_setcsr(m0);
}
static void runtf(const char *n, uint32_t b){
	float x; memcpy(&x,&b,4);
	unsigned m0=_mm_getcsr();
	_mm_setcsr((m0&~(0x3f|0x1f80))|0x1F00);
	trapped=0; volatile float s;
	if(sigsetjmp(jb,1)==0){ s=nearbyintf(x); }
	printf("%s bits=%x trap=%d r=%a\n",n,b,trapped,s);
	_mm_setcsr(m0);
}
int main(void){
	struct sigaction sa; memset(&sa,0,sizeof sa);
	sa.sa_handler=onfpe; sigaction(SIGFPE,&sa,0);
	runt("qnan0 ",0x7FF8000000000000ULL); runt("qnan1 ",0x7FF8000000000001ULL);
	runt("qnan62",0x7FF4000000000000ULL); runt("snan  ",0x7FF0000000000001ULL);
	runtf("qnan0f",0x7FC00000U); runtf("qnan1f",0x7FC00001U);
	runtf("qnan22f",0x7FA00000U); runtf("snanf ",0x7F800001U);
	return 0;
}
