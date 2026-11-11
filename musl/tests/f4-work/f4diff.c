/* F4 differential: transcribed-generic nearbyint refs vs arch candidates.
 * Candidates: nearbyint/nearbyintf (.s, roundsd/ss $0x0C + DAZ-gated
 * cold path; sacrificial ucomisd for DE-only flag fidelity).
 * Matrix: 4 rounding modes x DAZ{0,1} x FTZ{0,1}, directed + PRNG corpus.
 * Assertions per case:
 *   V: value bits identical, except sNaN inputs where quieting is
 *      allowed (cand == ref or cand == ref|QBIT); payload must match.
 *      ANY other value diff is a FAIL (no (b)-class expected: truth ==
 *      generic in all modes for nearbyint).
 *   PE: must be 0 on BOTH sides, always (harness clears before each
 *      call; generic wrapper clears it, suppress kills it). Any PE
 *      set is a hard FAIL (contract violation or harness bug).
 *   F: cand_flags must equal ref_flags exactly, except:
 *      - sNaN inputs: classified (both-IE / cand-only / ref-only /
 *        silent) and REPORTED, not auto-accepted (F4 has no D3 yet).
 *      - missing UE with FTZ=1 + subnormal/zero input + DAZ=0:
 *        accepted per F3 policy-4 analog (incidental flush), counted.
 * Exit 1 on any V fail, any PE, or any non-sNaN flag mismatch.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <fenv.h>
#include <pmmintrin.h>
double ref_nearbyint(double); float ref_nearbyintf(float);
double nearbyint(double); float nearbyintf(float);

static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}

static int vfails, ffails, pefails;
static long vtot, snan_quiet, snan_both_ie, snan_cand_ie, snan_ref_ie, snan_silent, ue_ftz;
static long vfn[2]; static long ffn[2];

static void checkd(int fn,double x,double rl,double cl,unsigned fl,unsigned fc,
	int rm,int daz,int ftz){
	uint64_t bl,bc; memcpy(&bl,&rl,8); memcpy(&bc,&cl,8);
	uint64_t xb; memcpy(&xb,&x,8);
	vtot++;
	int is_snan=((xb&0x7ff0000000000000ULL)==0x7ff0000000000000ULL)&&
		!(xb&0x0008000000000000ULL)&&(xb&0x0007ffffffffffffULL);
	int in_subz=((xb&0x7ff0000000000000ULL)==0);
	if(bl!=bc){
		if(is_snan&&(bc==(bl|0x0008000000000000ULL))){snan_quiet++; goto flags;}
		vfails++; vfn[fn]++;
		if(vfails<=10)printf("VFAIL fn=%d x=%a ref=%a[%lx] cand=%a[%lx] rm=%d daz=%d ftz=%d\n",
			fn,x,rl,bl,cl,bc,rm,daz,ftz);
		return;
	}
	if(is_snan) snan_quiet++;
flags:;
	if((fl|fc)&0x20U){
		pefails++;
		printf("PEFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
			fn,x,rl,fl,fc,rm,daz,ftz);
	}
	unsigned extra=fc&~fl, missing=fl&~fc;
	if(is_snan){
		if(extra==0x1U&&missing==0){snan_both_ie++;}
		else if(extra==0&&missing==0){snan_silent++;}
		else {
			if(extra==0x1U) snan_cand_ie++; else snan_ref_ie++;
			ffails++; ffn[fn]++;
			if(ffails<=10)printf("SNAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
				fn,x,rl,fl,fc,rm,daz,ftz);
		}
	} else if(extra||missing){
		if(missing==0x10U&&extra==0&&ftz==1&&in_subz&&daz==0){ue_ftz++;}
		else{ffails++; ffn[fn]++;
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	}
}
static void checkf(int fn,float x,float rl,float cl,unsigned fl,unsigned fc,
	int rm,int daz,int ftz){
	uint32_t bl,bc; memcpy(&bl,&rl,4); memcpy(&bc,&cl,4);
	uint32_t xb; memcpy(&xb,&x,4);
	vtot++;
	int is_snan=((xb&0x7f800000U)==0x7f800000U)&&
		!(xb&0x00400000U)&&(xb&0x003fffffU);
	int in_subz=((xb&0x7f800000U)==0);
	if(bl!=bc){
		if(is_snan&&(bc==(bl|0x00400000U))){snan_quiet++; goto flagsf;}
		vfails++; vfn[fn]++;
		if(vfails<=10)printf("VFAIL fn=%d x=%a ref=%a[%x] cand=%a[%x] rm=%d daz=%d ftz=%d\n",
			fn,x,rl,bl,cl,bc,rm,daz,ftz);
		return;
	}
	if(is_snan) snan_quiet++;
flagsf:;
	if((fl|fc)&0x20U){
		pefails++;
		printf("PEFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
			fn,x,rl,fl,fc,rm,daz,ftz);
	}
	unsigned extra=fc&~fl, missing=fl&~fc;
	if(is_snan){
		if(extra==0x1U&&missing==0){snan_both_ie++;}
		else if(extra==0&&missing==0){snan_silent++;}
		else {
			if(extra==0x1U) snan_cand_ie++; else snan_ref_ie++;
			ffails++; ffn[fn]++;
			if(ffails<=10)printf("SNAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
				fn,x,rl,fl,fc,rm,daz,ftz);
		}
	} else if(extra||missing){
		if(missing==0x10U&&extra==0&&ftz==1&&in_subz&&daz==0){ue_ftz++;}
		else{ffails++; ffn[fn]++; 
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	}
}

int main(void){
	static uint64_t dc[]={0x0000000000000000ULL,0x8000000000000000ULL,
		0x0000000000000001ULL,0x8000000000000001ULL,
		0x000FFFFFFFFFFFFFULL,0x800FFFFFFFFFFFFFULL,
		0x0010000000000000ULL,0x8010000000000000ULL,
		0x0010000000000001ULL,0x8010000000000001ULL,
		0x3FE0000000000000ULL,0xBFE0000000000000ULL,
		0x3FF8000000000000ULL,0xBFF8000000000000ULL,
		0x4004000000000000ULL,0xC004000000000000ULL,
		0x3FEFFFFFFFFFFFFFULL,0xBFEFFFFFFFFFFFFFULL,
		0x3FF0000000000000ULL,0xBFF0000000000000ULL,
		0x3FF0000000000001ULL,0xBFF0000000000001ULL,
		0x432FFFFFFFFFFFFFULL,0xC32FFFFFFFFFFFFFULL,
		0x4330000000000000ULL,0xC330000000000000ULL,
		0x4340000000000000ULL,0xC340000000000000ULL,
		0x7FF0000000000000ULL,0xFFF0000000000000ULL,
		0x7FF8000000000000ULL,0xFFF8000000000000ULL,
		0x7FF0000000000001ULL,0xFFF0000000000001ULL};
	static uint32_t fc[]={0x00000000U,0x80000000U,0x00000001U,0x80000001U,
		0x007FFFFFU,0x807FFFFFU,0x00800000U,0x80800000U,
		0x00800001U,0x80800001U,0x3F000000U,0xBF000000U,
		0x3FC00000U,0xBFC00000U,0x40200000U,0xC0200000U,
		0x3F7FFFFFU,0xBF7FFFFFU,0x3F800000U,0xBF800000U,
		0x3F800001U,0xBF800001U,0x4B7FFFFFU,0xCB7FFFFFU,
		0x4B800000U,0xCB800000U,0x7F800000U,0xFF800000U,
		0x7FC00000U,0xFFC00000U,0x7F800001U,0xFF800001U};
	unsigned mcsr0=_mm_getcsr();
	int rms[]={FE_TONEAREST,FE_DOWNWARD,FE_UPWARD,FE_TOWARDZERO};
	xst=0x9e3779b97f4a7c15ULL;
	for(int ri=0;ri<4;ri++)for(int daz=0;daz<2;daz++)for(int ftz=0;ftz<2;ftz++){
		fesetround(rms[ri]);
		_mm_setcsr((mcsr0&~(0x40|0x8000))|(daz?0x40:0)|(ftz?0x8000:0));
		for(int i=0;i<34;i++){
			double x; memcpy(&x,&dc[i],8);
			double rl,cl; unsigned fl,fc_;
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_nearbyint(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=nearbyint(x); fc_=_mm_getcsr()&0x3f;
			checkd(0,x,rl,cl,fl,fc_,ri,daz,ftz);
		}
		for(int i=0;i<32;i++){
			float x; memcpy(&x,&fc[i],4);
			float rl,cl; unsigned fl,fc_;
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_nearbyintf(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=nearbyintf(x); fc_=_mm_getcsr()&0x3f;
			checkf(1,x,rl,cl,fl,fc_,ri,daz,ftz);
		}
		for(int i=0;i<3000;i++){
			uint64_t r=rnd64(); double x; uint64_t b;
			switch(i%10){
			case 0: b=(r&0x8000000000000000ULL)|((r>>11)&0xFFFFFFFFFFFFULL)|1ULL; break;
			case 1: b=(r&0x8000000000000000ULL)|((((r>>11)%0x3FE)+1)<<52)|((r>>7)&0xFFFFFFFFFFFFULL); break;
			case 2: b=(r&0x8000000000000000ULL)|0x3FF0000000000000ULL|((r>>11)&0xFFFFFFFFFFFFULL); break;
			case 3: case 4: case 5:
				b=(r&0x8000000000000000ULL)|((((r>>11)%0x7FD)+1)<<52)|((r>>5)&0xFFFFFFFFFFFFULL); break;
			case 6: b=(r&0x8000000000000000ULL)|0x4320000000000000ULL|((r>>11)&0xFFFFFFFFFULL); break;
			case 7: b=(r&0x8000000000000000ULL)|0x4330000000000000ULL|((r>>11)&0xFFFFFFFFFFFFULL); break;
			case 8: {uint64_t m=(r>>20)&0xFFFFFFFFFFFFULL;
				b=(r&0x8000000000000000ULL)|0x7FF0000000000000ULL|((r>>63)?0x0008000000000000ULL:0)|((m?m:1)); break;}
			default: b=(r&1)?0:0x8000000000000000ULL; break;
			}
			memcpy(&x,&b,8);
			double rl,cl; unsigned fl,fc_;
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_nearbyint(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=nearbyint(x); fc_=_mm_getcsr()&0x3f;
			checkd(0,x,rl,cl,fl,fc_,ri,daz,ftz);
			uint32_t r2=(uint32_t)(rnd64()>>17); float xf; uint32_t bf;
			switch(i%10){
			case 0: bf=(r2&0x80000000U)|((r2>>9)&0x7FFFFFU)|1U; break;
			case 1: bf=(r2&0x80000000U)|(((((r2>>9)%0x7E))+1)<<23)|((r2>>6)&0x7FFFFFU); break;
			case 2: bf=(r2&0x80000000U)|0x3F800000U|((r2>>9)&0x7FFFFFU); break;
			case 3: case 4: case 5:
				bf=(r2&0x80000000U)|(((((r2>>9)%0xFD))+1)<<23)|((r2>>4)&0x7FFFFFU); break;
			case 6: bf=(r2&0x80000000U)|0x4B800000U|((r2>>9)&0xFFFFFU); break;
			case 7: bf=(r2&0x80000000U)|0x4C000000U|((r2>>9)&0x7FFFFFU); break;
			case 8: {uint32_t m=(r2>>12)&0x7FFFFFU;
				bf=(r2&0x80000000U)|0x7F800000U|((r2>>31)?0x00400000U:0)|((m?m:1)); break;}
			default: bf=(r2&1)?0:0x80000000U; break;
			}
			memcpy(&xf,&bf,4);
			float rfl,cfl;
			_mm_setcsr((_mm_getcsr())&~0x3f); rfl=ref_nearbyintf(xf); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cfl=nearbyintf(xf); fc_=_mm_getcsr()&0x3f;
			checkf(1,xf,rfl,cfl,fl,fc_,ri,daz,ftz);
		}
	}
	fesetround(FE_TONEAREST); _mm_setcsr(mcsr0);
	printf("f4diff: total=%ld vfails=%d ffails=%d pefails=%d snan_quiet=%ld both_ie=%ld cand_ie=%ld ref_ie=%ld silent=%ld ue_ftz=%ld\n",
		vtot,vfails,ffails,pefails,snan_quiet,snan_both_ie,snan_cand_ie,snan_ref_ie,snan_silent,ue_ftz);
	printf("vfn: %ld %ld\n", vfn[0],vfn[1]);
	printf("ffn: %ld %ld\n", ffn[0],ffn[1]);
	return (vfails||ffails||pefails)!=0;
}
