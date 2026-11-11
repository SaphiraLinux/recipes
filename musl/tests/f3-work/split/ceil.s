	.text
	.globl ceil
	.type ceil,@function
# double ceil(double x) — SSE4.1, DAZ-gated cold path (F3).
# Truth in both modes: ceil(+sub)=+1.0, ceil(-sub)=-0.0,
# ceil(±0)=±0 identity. Flags via sacrificial orig+1.0.
# No ldmxcsr anywhere; callee-saved and DF untouched.
ceil:
	movq %xmm0,%rax
	addq %rax,%rax
	shrq $53,%rax
	jnz .Lceil_arch
	movq %xmm0,%rcx		# cold entry: save orig bits
	subq $8,%rsp
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax	# DAZ?
	jnz .Lceil_daz1
	roundsd $0x0a,%xmm0,%xmm0	# DAZ=0: arch value (exact here)
	jmp .Lceil_sac
.Lceil_daz1:			# DAZ=1: integer fallback (truth)
	movq %rcx,%rax
	addq %rax,%rax
	jz .Lceil_sac		# ±0 -> identity
	testq %rcx,%rcx
	js .Lceil_neg
	movabs $0x3ff0000000000000,%rax	# +sub -> +1.0
	movq %rax,%xmm0
	jmp .Lceil_sac
.Lceil_neg:
	movabs $0x8000000000000000,%rax	# -sub -> -0.0
	movq %rax,%xmm0
	# fallthrough
.Lceil_sac:
	movabs $0x3ff0000000000000,%rax	# 1.0
	movq %rax,%xmm1
	movq %rcx,%xmm2
	addsd %xmm2,%xmm1	# sacrificial orig+1.0
	ret
.Lceil_arch:
	roundsd $0x0a,%xmm0,%xmm0	# suppress exceptions, round up
	ret
	.size ceil,.-ceil
	.section .note.GNU-stack,"",@progbits
