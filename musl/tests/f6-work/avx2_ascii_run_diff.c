/* Differential: avx2_ascii_run (v2, NUL-aware, maxlen-bounded) vs scalar ref.
 * Counts leading ASCII non-NUL bytes, stopping at first high-bit byte,
 * first NUL, or maxlen. Original Saphira test code under upstream musl
 * license (MIT, no change).
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
size_t avx2_ascii_run(const unsigned char *s, size_t maxlen);
static size_t ref_run(const unsigned char *s, size_t maxlen){
	size_t c=0;
	while(maxlen-->0){ unsigned char b=*s; if(b==0||(b&0x80)) break; s++; c++; }
	return c;
}
static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}
int main(void){
	static unsigned char big[256+64];
	long fails=0, total=0;
	xst=0x987654321fedcbaULL;
	for(int al=0;al<64;al++)for(int len=0;len<96;len++)for(int cls=0;cls<11;cls++){
		unsigned char *b=big+al;
		for(int i=0;i<len;i++){
			uint64_t r=rnd64();
			switch(cls){
			case 0: b[i]=(unsigned char)(0x20+(r%0x5F)); break; /* plain ASCII */
			case 1: b[i]=(i==0)?0:(unsigned char)(0x20+(r%0x5F)); break; /* NUL first */
			case 2: b[i]=(i==len-1)?0:0x41; break; /* NUL last */
			case 3: b[i]=(i==31||i==32||i==33||i==63||i==64)?0:0x41; break; /* NUL at block edges */
			case 4: b[i]=(i==0)?0xC3:0x41; break; /* non-ASCII first */
			case 5: b[i]=(i==len-1)?0x80:0x41; break; /* non-ASCII last */
			case 6: b[i]=(i==5)?0:((i==9)?0xC3:0x41); break; /* NUL(5) before nonASCII(9) */
			case 7: b[i]=(i==5)?0xC3:((i==9)?0:0x41); break; /* nonASCII(5) before NUL(9) */
			case 8: b[i]=(i%2)?0x41:0xC3; break; /* alternating */
			case 9: b[i]=(unsigned char)(r&0xFF); if(b[i]>=0x80&&b[i]<0xC0&&(i%3==0))b[i]=0x41; break;
			default:{ static const unsigned char m[]={0xE2,0x82,0xAC,0x41,0x00,0xF0,0x9F,0x98,0x80,0xC3,0xA9,0x7F};
				b[i]=m[i%12]; break; } /* multibyte incl embedded NUL */
			}
		}
		size_t e=ref_run(b,len), a=avx2_ascii_run(b,len);
		total++;
		if(e!=a){fails++; if(fails<10)printf("DIFF al=%d len=%d cls=%d exp=%zu got=%zu\n",al,len,cls,e,a);}
	}
	/* guard pages: mapped region ends exactly at PROT_NONE boundary */
	{
		size_t P=4096;
		unsigned char *map=mmap(0,2*P,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
		if(map==MAP_FAILED){printf("mmap failed\n");return 2;}
		if(mprotect(map+P,P,PROT_NONE)){printf("mprotect failed\n");return 2;}
		for(int off=0;off<64;off++){
			unsigned char *b=map+P-64+off;
			size_t room=64-off;
			for(size_t k=0;k<room;k++) b[k]=0x41;
			/* stop positions sweeping head/body/block edges/tail */
			for(int sp=-1;sp<=(int)room;sp+=1){
				for(int kind=0;kind<3;kind++){
					for(size_t k=0;k<room;k++) b[k]=0x41;
					if(sp>=0&&(size_t)sp<room) b[sp]=(kind==0)?0:(kind==1)?0xC3:0x80;
					for(size_t len=0;len<=room;len++){
						size_t e=ref_run(b,len), a=avx2_ascii_run(b,len);
						total++;
						if(e!=a){fails++; if(fails<15)printf("GUARDDIFF off=%d sp=%d kind=%d len=%zu exp=%zu got=%zu\n",off,sp,kind,len,e,a);}
					}
				}
			}
		}
		/* maxlen==0 on an unreadable page: must return 0 without fault */
		{
			unsigned char *np=map+P;
			size_t a=avx2_ascii_run(np,0);
			total++;
			if(a!=0){fails++; printf("ZEROLEN exp=0 got=%zu\n",a);}
		}
		munmap(map,2*P);
	}
	printf("avxrun_diff: total=%ld fails=%ld\n",total,fails);
	return fails!=0;
}
