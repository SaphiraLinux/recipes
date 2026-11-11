	.text
	.globl floorf
	.type floorf,@function
# float floorf(float x) — SSE4.1, DAZ-gated cold path (F3).
# Same design as floor (32-bit): truth in both modes, sacrificial
# orig+1.0f for flags. 1.0f = 0x3f800000.
floorf:
	movd %xmm0,%eax
	addl %eax,%eax		# drop sign; top 8 bits = biased exponent
	shrl $24,%eax		# 0 iff x is ±0 or subnormal
	jnz .Lfloorf_arch
	movd %xmm0,%ecx		# cold entry: save orig bits
	subq $8,%rsp
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax
	jnz .Lfloorf_daz1
	roundss $0x09,%xmm0,%xmm0
	jmp .Lfloorf_sac
.Lfloorf_daz1:
	movl %ecx,%eax
	addl %eax,%eax
	jz .Lfloorf_sac		# ±0 -> identity
	testl %ecx,%ecx
	js .Lfloorf_neg
	xorps %xmm0,%xmm0
	jmp .Lfloorf_sac
.Lfloorf_neg:
	movl $0xbf800000,%eax	# -sub -> -1.0f
	movd %eax,%xmm0
	# fallthrough
.Lfloorf_sac:
	movl $0x3f800000,%eax	# 1.0f
	movd %eax,%xmm1
	movd %ecx,%xmm2
	addss %xmm2,%xmm1	# sacrificial orig+1.0f
	ret
.Lfloorf_arch:
	roundss $0x09,%xmm0,%xmm0
	ret
	.size floorf,.-floorf
	.section .note.GNU-stack,"",@progbits
