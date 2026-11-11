/* Bench: avx2_ascii_run vs scalar ref on ASCII spans (short/long/aligned).
 * Original Saphira test code under upstream musl license (MIT, no change).
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
size_t avx2_ascii_run(const unsigned char *s, size_t maxlen);
static size_t ref_run(const unsigned char *s, size_t maxlen){
	size_t c=0;
	while(maxlen-->0){ unsigned char b=*s; if(b==0||(b&0x80)) break; s++; c++; }
	return c;
}
static double now(void){struct timespec t;clock_gettime(1,&t);return t.tv_sec+t.tv_nsec*1e-9;}
int main(void){
	static unsigned char big[4096+64] __attribute__((aligned(64)));
	memset(big,0x41,4096);
	__builtin_ia32_mfence();
	for(int tc=0;tc<4;tc++){
		size_t len=(tc==0)?7:((tc==1)?40:((tc==2)?200:1500));
		size_t al=(tc==3)?13:0;
		unsigned char *b=big+al;
		volatile size_t sink=0;
		double t0=now();
		for(long i=0;i<2000000;i++){sink+=ref_run(b,len);}
		double t1=now();
		for(long i=0;i<2000000;i++){sink+=avx2_ascii_run(b,len);}
		double t2=now();
		printf("len=%zu al=%zu ref=%.3fns avx=%.3fns speedup=%.2f sink=%zu\n",
			len,al,(t1-t0)/2000000*1e9,(t2-t1)/2000000*1e9,
			(t1-t0)/(t2-t1),(size_t)sink);
	}
	return 0;
}
