/* F4 trap parity: ref (generic wrapper) vs cand (arch $0x0C), unmasked traps.
 * Masks: each of IM/DM/ZM/OM/UM/PM singly + all. Full RM x DAZ x FTZ.
 * Records (fn, side, input, mask) SIGFPEs via siglongjmp. Exit 0 + report.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <fenv.h>
#include <pmmintrin.h>
double ref_nearbyint(double); float ref_nearbyintf(float);
double nearbyint(double); float nearbyintf(float);

static sigjmp_buf jb;
static volatile int trapped;
static void onfpe(int s){(void)s; trapped=1; siglongjmp(jb,1);}

static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}

static long ref_traps, cand_traps, ref_only, cand_only;
static long rob[2][7], cob[2][7];
static int detail_cap = 12;

int main(void){
	struct sigaction sa; memset(&sa,0,sizeof sa);
	sa.sa_handler=onfpe; sigaction(SIGFPE,&sa,0);
	static uint64_t dc[]={0x0000000000000000ULL,0x8000000000000000ULL,
		0x0000000000000001ULL,0x8000000000000001ULL,
		0x000FFFFFFFFFFFFFULL,0x800FFFFFFFFFFFFFULL,
		0x0010000000000000ULL,0x8010000000000000ULL,
		0x3FE0000000000000ULL,0xBFE0000000000000ULL,
		0x3FF8000000000000ULL,0xBFF8000000000000ULL,
		0x4004000000000000ULL,0xC004000000000000ULL,
		0x4330000000000000ULL,0xC330000000000000ULL,
		0x7FF0000000000000ULL,0xFFF0000000000000ULL,
		0x7FF8000000000001ULL,0xFFF8000000000001ULL,
		0x7FF0000000000001ULL,0xFFF0000000000001ULL,
		0x7FF4000000000000ULL,0xFFF4000000000000ULL};
	static uint32_t fc[]={0x00000000U,0x80000000U,0x00000001U,0x80000001U,
		0x007FFFFFU,0x807FFFFFU,0x00800000U,0x80800000U,
		0x3F000000U,0xBF000000U,0x3FC00000U,0xBFC00000U,
		0x40200000U,0xC0200000U,0x4B800000U,0xCB800000U,
		0x7F800000U,0xFF800000U,0x7FC00001U,0xFFC00001U,
		0x7F800001U,0xFF800001U,0x7FA00000U,0xFFA00000U};
	int masks[]={0x1F00,0x1E80,0x1D80,0x1B80,0x1780,0x0F80,0x0000};
	const char *mn[]={"IM","DM","ZM","OM","UM","PM","ALL"};
	unsigned mcsr0=_mm_getcsr();
	int rms[]={FE_TONEAREST,FE_DOWNWARD,FE_UPWARD,FE_TOWARDZERO};
	xst=0x51ab3d7f9e2c4861ULL;
	for(int mi=0;mi<7;mi++)for(int ri=0;ri<4;ri++)
	for(int daz=0;daz<2;daz++)for(int ftz=0;ftz<2;ftz++){
		fesetround(rms[ri]);
		unsigned base=(mcsr0&~(0x3f|0x1f80));
		base|=(daz?0x40:0)|(ftz?0x8000:0);
		for(int i=0;i<24;i++){
			double x; memcpy(&x,&dc[i],8);
			volatile double sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=ref_nearbyint(x); }
			int rt=trapped; (void)sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=nearbyint(x); }
			int ct=trapped; (void)sink;
			if(rt){ref_traps++;rob[0][mi]++;}
			if(ct){cand_traps++;cob[0][mi]++;}
			if(rt&&!ct){ref_only++; if(detail_cap>0){detail_cap--; printf("REF-ONLY fn=0 x=%a mask=%s rm=%d daz=%d ftz=%d\n",x,mn[mi],ri,daz,ftz);} }
			if(ct&&!rt){cand_only++; if(detail_cap>0){detail_cap--; printf("CAND-ONLY fn=0 x=%a mask=%s rm=%d daz=%d ftz=%d\n",x,mn[mi],ri,daz,ftz);} }
		}
		for(int i=0;i<24;i++){
			float x; memcpy(&x,&fc[i],4);
			volatile float sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=ref_nearbyintf(x); }
			int rt=trapped; (void)sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=nearbyintf(x); }
			int ct=trapped; (void)sink;
			if(rt){ref_traps++;rob[1][mi]++;}
			if(ct){cand_traps++;cob[1][mi]++;}
			if(rt&&!ct){ref_only++; if(detail_cap>0){detail_cap--; printf("REF-ONLY fn=1 x=%a mask=%s rm=%d daz=%d ftz=%d\n",x,mn[mi],ri,daz,ftz);} }
			if(ct&&!rt){cand_only++; if(detail_cap>0){detail_cap--; printf("CAND-ONLY fn=1 x=%a mask=%s rm=%d daz=%d ftz=%d\n",x,mn[mi],ri,daz,ftz);} }
		}
		for(int i=0;i<500;i++){
			uint64_t r=rnd64(); double x; uint64_t b;
			switch(i%10){
			case 0: b=(r&0x8000000000000000ULL)|((r>>11)&0xFFFFFFFFFFFFULL)|1ULL; break;
			case 1: case 2: case 3:
				b=(r&0x8000000000000000ULL)|((((r>>11)%0x7FD)+1)<<52)|((r>>5)&0xFFFFFFFFFFFFULL); break;
			case 4: b=(r&0x8000000000000000ULL)|0x3FF0000000000000ULL|((r>>11)&0xFFFFFFFFFFFFULL); break;
			case 5: b=(r&0x8000000000000000ULL)|0x4330000000000000ULL|((r>>11)&0xFFFFFFFFFFFFULL); break;
			case 6: {uint64_t m=(r>>20)&0xFFFFFFFFFFFFULL;
				b=(r&0x8000000000000000ULL)|0x7FF0000000000000ULL|((r>>63)?0x0008000000000000ULL:0)|((m?m:1)); break;}
			default: b=(r&1)?0:0x8000000000000000ULL; break;
			}
			memcpy(&x,&b,8);
			volatile double sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=ref_nearbyint(x); }
			int rt=trapped; (void)sink;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sink=nearbyint(x); }
			int ct=trapped; (void)sink;
			if(rt)ref_traps++; if(ct)cand_traps++;
			if(rt&&!ct)ref_only++;
			if(ct&&!rt)cand_only++;
			uint32_t r2=(uint32_t)(rnd64()>>17); float xf; uint32_t bf;
			switch(i%10){
			case 0: bf=(r2&0x80000000U)|((r2>>9)&0x7FFFFFU)|1U; break;
			case 1: case 2: case 3:
				bf=(r2&0x80000000U)|(((((r2>>9)%0xFD))+1)<<23)|((r2>>4)&0x7FFFFFU); break;
			case 4: bf=(r2&0x80000000U)|0x3F800000U|((r2>>9)&0x7FFFFFU); break;
			case 5: bf=(r2&0x80000000U)|0x4B800000U|((r2>>9)&0xFFFFFU); break;
			case 6: {uint32_t m=(r2>>12)&0x7FFFFFU;
				bf=(r2&0x80000000U)|0x7F800000U|((r2>>31)?0x00400000U:0)|((m?m:1)); break;}
			default: bf=(r2&1)?0:0x80000000U; break;
			}
			memcpy(&xf,&bf,4);
			volatile float sinkf;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sinkf=ref_nearbyintf(xf); }
			rt=trapped; (void)sinkf;
			_mm_setcsr((base&~0x1f80)|masks[mi]);
			trapped=0;
			if(sigsetjmp(jb,1)==0){ sinkf=nearbyintf(xf); }
			ct=trapped; (void)sinkf;
			if(rt)ref_traps++; if(ct)cand_traps++;
			if(rt&&!ct)ref_only++;
			if(ct&&!rt)cand_only++;
		}
	}
	fesetround(FE_TONEAREST); _mm_setcsr(mcsr0);
	printf("f4trap: ref_traps=%ld cand_traps=%ld ref_only=%ld cand_only=%ld\n",
		ref_traps,cand_traps,ref_only,cand_only);
	for(int f=0;f<2;f++)for(int m=0;m<7;m++)
		if(rob[f][m]||cob[f][m])
			printf("tbucket fn=%d mask=%d ref=%ld cand=%ld\n",f,m,rob[f][m],cob[f][m]);
	return 0;
}
