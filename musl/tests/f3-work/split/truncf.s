	.text
	.globl truncf
	.type truncf,@function
# float truncf(float x) — SSE4.1, DAZ-gated cold path (F3).
# Same design as trunc (32-bit shifts): signed zero in both modes,
# sacrificial orig+1.0f for flags.
truncf:
	movd %xmm0,%eax
	addl %eax,%eax
	shrl $24,%eax
	jnz .Ltruncf_arch
	movd %xmm0,%ecx		# cold entry: save orig bits
	subq $8,%rsp
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax
	jnz .Ltruncf_daz1
	roundss $0x0b,%xmm0,%xmm0
	jmp .Ltruncf_sac
.Ltruncf_daz1:
	testl %ecx,%ecx
	js .Ltruncf_neg
	xorps %xmm0,%xmm0
	jmp .Ltruncf_sac
.Ltruncf_neg:
	movl %ecx,%eax
	shrl $31,%eax
	shll $31,%eax		# 0x80000000
	movd %eax,%xmm0		# -0.0f
	# fallthrough
.Ltruncf_sac:
	movl $0x3f800000,%eax	# 1.0f
	movd %eax,%xmm1
	movd %ecx,%xmm2
	addss %xmm2,%xmm1	# sacrificial orig+1.0f
	ret
.Ltruncf_arch:
	roundss $0x0b,%xmm0,%xmm0
	ret
	.size truncf,.-truncf
	.section .note.GNU-stack,"",@progbits
