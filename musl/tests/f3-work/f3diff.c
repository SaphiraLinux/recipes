/* F3 differential: transcribed-generic refs vs arch candidates.
 * Candidates: floor/floorf/ceil/ceilf/trunc/truncf (.s with DAZ-gated
 * cold path) + gated rint/rintf (0011).
 * Matrix: 4 rounding modes x DAZ{0,1} x FTZ{0,1}, directed + PRNG corpus.
 * Assertions per case:
 *   V: value bits identical, except sNaN inputs where quieting is allowed
 *      (cand == ref or cand == ref|QBIT); payload must otherwise match.
 *   F: cand_flags subset of ref_flags; silence allowed ONLY for PE (D1).
 * Reports value/flag failures with detail (capped), plus PE-silence and
 * sNaN-quiet event counts (D1/D3 evidence). Exit 1 on any V or F failure.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <fenv.h>
#include <pmmintrin.h>
double ref_floor(double); float ref_floorf(float);
double ref_ceil(double); float ref_ceilf(float);
double ref_trunc(double); float ref_truncf(float);
double ref_rint(double); float ref_rintf(float);
double floor(double); float floorf(float);
double ceil(double); float ceilf(float);
double trunc(double); float truncf(float);
double rint(double); float rintf(float);

static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}

static int vfails, ffails;
static long vtot, pe_silence, snan_quiet, snan_ie, snan_silent, ue_ftz;
static long vfn[8]; static long ffn[8]; static long ffn_d0sub[8];
static long vb[8][2]; static long fb[8][2][2][4];

static void checkd(int fn,double x,double rl,double cl,unsigned fl,unsigned fc,
	int rm,int daz,int ftz){
	uint64_t bl,bc; memcpy(&bl,&rl,8); memcpy(&bc,&cl,8);
	vtot++;
	int is_snan=((bl&0x7ff0000000000000ULL)==0x7ff0000000000000ULL)&&
		!(bl&0x0008000000000000ULL)&&(bl&0x0007ffffffffffffULL);
	if(bl!=bc){
		if(is_snan&&(bc==(bl|0x0008000000000000ULL))){snan_quiet++; goto flags;}
		vfails++; vfn[fn]++; vb[fn][daz]++;
		if(vfails<=10)printf("VFAIL fn=%d x=%a ref=%a[%lx] cand=%a[%lx] rm=%d daz=%d ftz=%d\n",
			fn,x,rl,bl,cl,bc,rm,daz,ftz);
		return;
	}
	if(is_snan) snan_quiet++;
flags:;
	{
	uint64_t xb; memcpy(&xb,&x,8);
	int in_snan=((xb&0x7ff0000000000000ULL)==0x7ff0000000000000ULL)&&
		!(xb&0x0008000000000000ULL)&&(xb&0x0007ffffffffffffULL);
	int in_subz=((xb&0x7ff0000000000000ULL)==0);
	unsigned extra=fc&~fl, missing=fl&~fc;
	if(in_snan){
		/* D3-masked: cand raises IE on sNaN, generic silent. If BOTH
		 * sides are silent (generic-vs-generic control), count as
		 * snan_silent — values and flags already proven equal. */
		if(extra==0x1U&&missing==0){snan_ie++;}
		else if(extra==0&&missing==0){snan_silent++;}
		else{ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [snan]\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	} else if(extra){
		ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
		if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [extra]\n",
			fn,x,rl,fl,fc,rm,daz,ftz);
	} else if(missing&~0x20U){
		/* (4): UE from generic's FTZ-flushed intermediate is incidental;
		 * allowed iff FTZ=1, subnormal-or-zero input, DAZ=0. */
		if(missing==0x10U&&ftz==1&&in_subz&&daz==0){ue_ftz++;}
		else{ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
			if(in_subz&&daz==0) ffn_d0sub[fn]++;
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [missing]\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	} else if(missing){ pe_silence++; }
	}
}
static void checkf(int fn,float x,float rl,float cl,unsigned fl,unsigned fc,
	int rm,int daz,int ftz){
	uint32_t bl,bc; memcpy(&bl,&rl,4); memcpy(&bc,&cl,4);
	vtot++;
	int is_snan=((bl&0x7f800000U)==0x7f800000U)&&
		!(bl&0x00400000U)&&(bl&0x003fffffU);
	if(bl!=bc){
		if(is_snan&&(bc==(bl|0x00400000U))){snan_quiet++; goto flagsf;}
		vfails++; vfn[fn]++; vb[fn][daz]++;
		if(vfails<=10)printf("VFAIL fn=%d x=%a ref=%a[%x] cand=%a[%x] rm=%d daz=%d ftz=%d\n",
			fn,x,rl,bl,cl,bc,rm,daz,ftz);
		return;
	}
	if(is_snan) snan_quiet++;
flagsf:;
	{
	uint32_t xb; memcpy(&xb,&x,4);
	int in_snan=((xb&0x7f800000U)==0x7f800000U)&&
		!(xb&0x00400000U)&&(xb&0x003fffffU);
	int in_subz=((xb&0x7f800000U)==0);
	unsigned extra=fc&~fl, missing=fl&~fc;
	if(in_snan){
		/* D3-masked: cand raises IE on sNaN, generic silent. If BOTH
		 * sides are silent (generic-vs-generic control), count as
		 * snan_silent — values and flags already proven equal. */
		if(extra==0x1U&&missing==0){snan_ie++;}
		else if(extra==0&&missing==0){snan_silent++;}
		else{ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [snan]\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	} else if(extra){
		ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
		if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [extra]\n",
			fn,x,rl,fl,fc,rm,daz,ftz);
	} else if(missing&~0x20U){
		if(missing==0x10U&&ftz==1&&in_subz&&daz==0){ue_ftz++;}
		else{ffails++; ffn[fn]++; fb[fn][daz][ftz][rm]++;
			if(in_subz&&daz==0) ffn_d0sub[fn]++;
			if(ffails<=10)printf("FFAIL fn=%d x=%a ref=%a rfl=%x cfl=%x rm=%d daz=%d ftz=%d [missing]\n",
				fn,x,rl,fl,fc,rm,daz,ftz);}
	} else if(missing){ pe_silence++; }
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
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_floor(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=floor(x); fc_=_mm_getcsr()&0x3f;
			checkd(0,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_ceil(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=ceil(x); fc_=_mm_getcsr()&0x3f;
			checkd(1,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_trunc(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=trunc(x); fc_=_mm_getcsr()&0x3f;
			checkd(2,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_rint(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=rint(x); fc_=_mm_getcsr()&0x3f;
			checkd(3,x,rl,cl,fl,fc_,ri,daz,ftz);
		}
		for(int i=0;i<32;i++){
			float x; memcpy(&x,&fc[i],4);
			float rl,cl; unsigned fl,fc_;
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_floorf(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=floorf(x); fc_=_mm_getcsr()&0x3f;
			checkf(4,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_ceilf(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=ceilf(x); fc_=_mm_getcsr()&0x3f;
			checkf(5,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_truncf(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=truncf(x); fc_=_mm_getcsr()&0x3f;
			checkf(6,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_rintf(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=rintf(x); fc_=_mm_getcsr()&0x3f;
			checkf(7,x,rl,cl,fl,fc_,ri,daz,ftz);
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
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_floor(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=floor(x); fc_=_mm_getcsr()&0x3f;
			checkd(0,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_ceil(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=ceil(x); fc_=_mm_getcsr()&0x3f;
			checkd(1,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_trunc(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=trunc(x); fc_=_mm_getcsr()&0x3f;
			checkd(2,x,rl,cl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rl=ref_rint(x); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cl=rint(x); fc_=_mm_getcsr()&0x3f;
			checkd(3,x,rl,cl,fl,fc_,ri,daz,ftz);
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
			_mm_setcsr((_mm_getcsr())&~0x3f); rfl=ref_floorf(xf); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cfl=floorf(xf); fc_=_mm_getcsr()&0x3f;
			checkf(4,xf,rfl,cfl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rfl=ref_ceilf(xf); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cfl=ceilf(xf); fc_=_mm_getcsr()&0x3f;
			checkf(5,xf,rfl,cfl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rfl=ref_truncf(xf); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cfl=truncf(xf); fc_=_mm_getcsr()&0x3f;
			checkf(6,xf,rfl,cfl,fl,fc_,ri,daz,ftz);
			_mm_setcsr((_mm_getcsr())&~0x3f); rfl=ref_rintf(xf); fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); cfl=rintf(xf); fc_=_mm_getcsr()&0x3f;
			checkf(7,xf,rfl,cfl,fl,fc_,ri,daz,ftz);
		}
	}
	fesetround(FE_TONEAREST); _mm_setcsr(mcsr0);
	printf("f3diff: total=%ld vfails=%d ffails=%d pe_silence=%ld snan_quiet=%ld snan_ie=%ld snan_silent=%ld ue_ftz=%ld\n",
		vtot,vfails,ffails,pe_silence,snan_quiet,snan_ie,snan_silent,ue_ftz);
	printf("vfn: %ld %ld %ld %ld %ld %ld %ld %ld\n",
		vfn[0],vfn[1],vfn[2],vfn[3],vfn[4],vfn[5],vfn[6],vfn[7]);
	printf("ffn: %ld %ld %ld %ld %ld %ld %ld %ld\n",
		ffn[0],ffn[1],ffn[2],ffn[3],ffn[4],ffn[5],ffn[6],ffn[7]);
	printf("ffn_daz0_subclass: %ld %ld %ld %ld %ld %ld %ld %ld\n",
		ffn_d0sub[0],ffn_d0sub[1],ffn_d0sub[2],ffn_d0sub[3],
		ffn_d0sub[4],ffn_d0sub[5],ffn_d0sub[6],ffn_d0sub[7]);
	for(int f=0;f<8;f++)for(int d=0;d<2;d++)for(int t=0;t<2;t++)for(int r=0;r<4;r++)
		if(fb[f][d][t][r])
			printf("bucket fn=%d daz=%d ftz=%d rm=%d fFails=%ld\n",f,d,t,r,fb[f][d][t][r]);
	for(int f=0;f<8;f++)for(int d=0;d<2;d++)
		if(vb[f][d]) printf("vbucket fn=%d daz=%d vFails=%ld\n",f,d,vb[f][d]);
	return (vfails||ffails)!=0;
}
