	.text
	.globl nearbyintf
	.type nearbyintf,@function
# float nearbyintf(float x) — SSE4.1, DAZ-gated cold path (F4).
# Same design as nearbyint (32-bit): MXCSR mode, never inexact,
# sacrificial ucomisd orig,0.0f for DE-only flag fidelity.
nearbyintf:
	movd %xmm0,%eax
	addl %eax,%eax		# drop sign; top 8 bits = biased exponent
	shrl $24,%eax		# 0 iff x is ±0 or subnormal
	jnz .Lni_arch
	movd %xmm0,%ecx		# cold entry: save orig bits
	movl %ecx,%eax
	addl %eax,%eax
	jz .Lni_arch		# ±0: arch value, exact and silent
	subq $8,%rsp		# subnormal: test DAZ
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax
	jnz .Lni_arch		# DAZ=1: arch value+flags correct
	roundss $0x0c,%xmm0,%xmm0
	xorps %xmm1,%xmm1
	movd %ecx,%xmm2
	ucomiss %xmm1,%xmm2	# sacrificial: DE iff denormal input, never PE
	ret
.Lni_arch:
	roundss $0x0c,%xmm0,%xmm0
	ret
	.size nearbyintf,.-nearbyintf
	.section .note.GNU-stack,"",@progbits
