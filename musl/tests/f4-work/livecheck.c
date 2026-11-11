#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <pmmintrin.h>
double ref_nearbyint(double); float ref_nearbyintf(float);
double nearbyint(double); float nearbyintf(float);
int main(void){
	unsigned mcsr0=_mm_getcsr();
	static uint64_t dc[]={0x0000000000000000ULL,0x8000000000000000ULL,
		0x0000000000000001ULL,0x8000000000000001ULL,
		0x000FFFFFFFFFFFFFULL,0x800FFFFFFFFFFFFFULL,
		0x0010000000000000ULL,0x8010000000000000ULL,
		0x3FE0000000000000ULL,0xBFE0000000000000ULL,
		0x3FF8000000000000ULL,0xBFF8000000000000ULL,
		0x4004000000000000ULL,0xC004000000000000ULL,
		0x4330000000000000ULL,0xC330000000000000ULL,
		0x7FF0000000000000ULL,0xFFF0000000000000ULL,
		0x7FF8000000000000ULL,0xFFF8000000000000ULL,
		0x7FF0000000000001ULL,0xFFF0000000000001ULL};
	int fails=0,total=0;
	for(int daz=0;daz<2;daz++){
		_mm_setcsr((mcsr0&~0x40)|(daz?0x40:0));
		for(int i=0;i<22;i++){
			double x; memcpy(&x,&dc[i],8);
			_mm_setcsr((_mm_getcsr())&~0x3f); double rl=ref_nearbyint(x); unsigned fl=_mm_getcsr()&0x3f;
			_mm_setcsr((_mm_getcsr())&~0x3f); double cl=nearbyint(x); unsigned fc=_mm_getcsr()&0x3f;
			total++;
			uint64_t bl,bc; memcpy(&bl,&rl,8); memcpy(&bc,&cl,8);
			if(bl!=bc){fails++; if(fails<6)printf("VAL x=%a live=%a[%lx] ref=%a[%lx] daz=%d\n",x,cl,bc,rl,bl,daz);}
			else if(fl!=fc){fails++; if(fails<10)printf("FLAG x=%a livefl=%x reffl=%x daz=%d\n",x,fc,fl,daz);}
		}
	}
	_mm_setcsr(mcsr0);
	printf("livecheck: total=%d fails=%d\n",total,fails);
	return fails!=0;
}
