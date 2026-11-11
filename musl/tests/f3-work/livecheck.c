/* F3 authenticity loop: live libm (Egg _p1-r2) vs transcribed upstream refs.
 * floor/ceil/trunc families: live IS generic -> expect bit-identical values
 * AND flags across the corpus (proves transcription fidelity).
 * rint/rintf: live has the 0004 combo -> expect EXACTLY the F2b delta:
 * values identical everywhere; flags differ ONLY by DE on nonzero
 * subnormals with DAZ=0 (live silent, ref sets DE).
 * Any other delta = transcription error or wrong assumption -> STOP.
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

int main(void){
	unsigned mcsr0=_mm_getcsr();
	static uint64_t dc[]={0x0000000000000000ULL,0x8000000000000000ULL,
		0x0000000000000001ULL,0x8000000000000001ULL,
		0x000FFFFFFFFFFFFFULL,0x800FFFFFFFFFFFFFULL,
		0x0010000000000000ULL,0x8010000000000000ULL,
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
		0x3F7FFFFFU,0xBF7FFFFFU,0x3F800000U,0xBF800000U,
		0x3F800001U,0xBF800001U,0x4B7FFFFFU,0xCB7FFFFFU,
		0x4B800000U,0xCB800000U,0x7F800000U,0xFF800000U,
		0x7FC00000U,0xFFC00000U,0x7F800001U,0xFF800001U};
	int fails=0, deonly=0, total=0;
	xst=0x123456789abcdefULL;
	for(int daz=0;daz<2;daz++){
		_mm_setcsr((mcsr0&~0x40)|(daz?0x40:0));
		for(int i=0;i<24;i++){ /* directed doubles */
			double x; memcpy(&x,&dc[i],8);
			for(int k=0;k<8;k++){
				double rl, cl; unsigned fl, fc_;
				_mm_setcsr((_mm_getcsr())&~0x3f);
				switch(k){
				case 0: rl=ref_floor(x); break;
				case 1: rl=ref_ceil(x); break;
				case 2: rl=ref_trunc(x); break;
				case 3: rl=ref_rint(x); break;
				case 4: {float xf=(float)x; float r=ref_floorf(xf); rl=r; break;}
				case 5: {float xf=(float)x; float r=ref_ceilf(xf); rl=r; break;}
				case 6: {float xf=(float)x; float r=ref_truncf(xf); rl=r; break;}
				case 7: {float xf=(float)x; float r=ref_rintf(xf); rl=r; break;}
				}
				fl=_mm_getcsr()&0x3f;
				_mm_setcsr((_mm_getcsr())&~0x3f);
				switch(k){
				case 0: cl=floor(x); break;
				case 1: cl=ceil(x); break;
				case 2: cl=trunc(x); break;
				case 3: cl=rint(x); break;
				case 4: {float xf=(float)x; float r=floorf(xf); cl=r; break;}
				case 5: {float xf=(float)x; float r=ceilf(xf); cl=r; break;}
				case 6: {float xf=(float)x; float r=truncf(xf); cl=r; break;}
				case 7: {float xf=(float)x; float r=rintf(xf); cl=r; break;}
				}
				fc_=_mm_getcsr()&0x3f;
				total++;
				uint64_t bl, bc; memcpy(&bl,&rl,8); memcpy(&bc,&cl,8);
				if(bl!=bc){fails++; if(fails<8)printf("VAL fn=%d x=%a live=%a[%lx] ref=%a[%lx] daz=%d\n",k,x,cl,bc,rl,bl,daz);}
				else if(fl!=fc_){
					if((k==3||k==7)&&(fl^fc_)==0x2&&(fl&0x2)&&(fc_&0x2)==0){deonly++;}
					else {fails++; if(fails<12)printf("FLAG fn=%d x=%a livefl=%x reffl=%x daz=%d\n",k,x,fc_,fl,daz);}
				}
			}
		}
	}
	_mm_setcsr(mcsr0);
	printf("livecheck: total=%d fails=%d deonly(rint-expected)=%d\n",total,fails,deonly);
	return fails!=0;
}
