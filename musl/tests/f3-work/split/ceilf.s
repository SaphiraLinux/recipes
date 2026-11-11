	.text
	.globl ceilf
	.type ceilf,@function
# float ceilf(float x) — SSE4.1, DAZ-gated cold path (F3).
# Same design as ceil (32-bit): truth in both modes, sacrificial
# orig+1.0f for flags. +1.0f = 0x3f800000.
ceilf:
	movd %xmm0,%eax
	addl %eax,%eax
	shrl $24,%eax
	jnz .Lceilf_arch
	movd %xmm0,%ecx		# cold entry: save orig bits
	subq $8,%rsp
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax
	jnz .Lceilf_daz1
	roundss $0x0a,%xmm0,%xmm0
	jmp .Lceilf_sac
.Lceilf_daz1:
	movl %ecx,%eax
	addl %eax,%eax
	jz .Lceilf_sac		# ±0 -> identity
	testl %ecx,%ecx
	js .Lceilf_neg
	movl $0x3f800000,%eax	# +sub -> +1.0f
	movd %eax,%xmm0
	jmp .Lceilf_sac
.Lceilf_neg:
	movl $0x80000000,%eax	# -sub -> -0.0f
	movd %eax,%xmm0
	# fallthrough
.Lceilf_sac:
	movl $0x3f800000,%eax	# 1.0f
	movd %eax,%xmm1
	movd %ecx,%xmm2
	addss %xmm2,%xmm1	# sacrificial orig+1.0f
	ret
.Lceilf_arch:
	roundss $0x0a,%xmm0,%xmm0
	ret
	.size ceilf,.-ceilf
	.section .note.GNU-stack,"",@progbits
