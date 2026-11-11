/* Exhaustive differential: avx2_ascii_span vs scalar reference.
 * Alignments 0..63, lengths 0..96, content classes incl. NULs,
 * first/last non-ASCII, alternating, random, multibyte sequences.
 * Plus guard-page tests (PROT_NONE page after buffer end).
 * Original Saphira test code under upstream musl license (MIT, no change).
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
size_t avx2_ascii_span(const unsigned char *s, size_t n);
static size_t ref_span(const unsigned char *s, size_t n){
	size_t c=0; while(n-->0 && !(*s&0x80)){s++;c++;} return c;
}
static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}
int main(void){
	static unsigned char big[256+64];
	long fails=0, total=0;
	xst=0x123456789abcdefULL;
	for(int al=0;al<64;al++)for(int len=0;len<96;len++)for(int cls=0;cls<6;cls++){
		unsigned char *b=big+al;
		for(int i=0;i<len;i++){
			uint64_t r=rnd64();
			switch(cls){
			case 0: b[i]=(unsigned char)(0x20+(r%0x5F)); break;
			case 1: b[i]=(i==0)?0xC3:(unsigned char)(r&0xFF); break;
			case 2: b[i]=(i%2)?0x41:0xC3; break;
			case 3: b[i]=(i==len-1)?0x80:0x41; break;
			case 4: b[i]=(i%7==0)?0:(unsigned char)(r&0xFF); break;
			default: b[i]=(unsigned char)(r&0xFF); if(b[i]>=0x80&&b[i]<0xC0&&(i%3==0))b[i]=0x41; break;
			}
		}
		size_t e=ref_span(b,len), a=avx2_ascii_span(b,len);
		total++;
		if(e!=a){fails++; if(fails<10)printf("DIFF al=%d len=%d cls=%d exp=%zu got=%zu\n",al,len,cls,e,a);}
	}
	/* multibyte sequences */
	{
		unsigned char m[]={0xE2,0x82,0xAC,0x41,0xF0,0x9F,0x98,0x80,0x00,0xC3,0xA9,0x7F};
		for(int al=0;al<64;al+=7)for(int len=0;len<=12;len++){
			memcpy(big+al,m,len>12?12:len);
			size_t e=ref_span(big+al,len), a=avx2_ascii_span(big+al,len);
			total++;
			if(e!=a){fails++; if(fails<10)printf("MBDIFF al=%d len=%d exp=%zu got=%zu\n",al,len,e,a);}
		}
	}
	/* guard pages: buffer ends exactly at PROT_NONE boundary */
	{
		size_t P=4096;
		unsigned char *map=mmap(0,2*P,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
		if(map==MAP_FAILED){printf("mmap failed\n");return 2;}
		if(mprotect(map+P,P,PROT_NONE)){printf("mprotect failed\n");return 2;}
		for(int off=0;off<64;off++){
			unsigned char *b=map+P-64+off; /* last 64-off bytes usable */
			size_t room=64-off;
			for(size_t k=0;k<room;k++) b[k]=(k%5==4)?0xC3:0x41;
			for(size_t len=0;len<=room;len++){
				size_t e=ref_span(b,len), a=avx2_ascii_span(b,len);
				total++;
				if(e!=a){fails++; printf("GUARDDIFF off=%d len=%zu exp=%zu got=%zu\n",off,len,e,a);}
			}
		}
		/* all-ASCII right up to the boundary, maxlen spanning it */
		{
			unsigned char *b=map+P-64;
			memset(b,0x41,64);
			size_t e=ref_span(b,64), a=avx2_ascii_span(b,64);
			total++;
			if(e!=a){fails++; printf("GUARDBOUNDARY exp=%zu got=%zu\n",e,a);}
		}
		munmap(map,2*P);
	}
	printf("avxdiff: total=%ld fails=%ld\n",total,fails);
	return fails!=0;
}
