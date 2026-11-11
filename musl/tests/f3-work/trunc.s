	.text
	.globl trunc
	.type trunc,@function
# double trunc(double x) — SSE4.1, DAZ-gated cold path (F3).
# Truth in both modes: trunc(±sub-or-0) = signed zero.
# Flags via sacrificial orig+1.0 (see floor.s).
trunc:
	movq %xmm0,%rax
	addq %rax,%rax
	shrq $53,%rax
	jnz .Ltrunc_arch
	movq %xmm0,%rcx		# cold entry: save orig bits
	subq $8,%rsp
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax	# DAZ?
	jnz .Ltrunc_daz1
	roundsd $0x0b,%xmm0,%xmm0	# DAZ=0: arch value (exact here)
	jmp .Ltrunc_sac
.Ltrunc_daz1:			# DAZ=1: signed zero via DAZ-free ops
	testq %rcx,%rcx
	js .Ltrunc_neg
	xorpd %xmm0,%xmm0	# + -> +0.0
	jmp .Ltrunc_sac
.Ltrunc_neg:
	movq %rcx,%rax
	shrq $63,%rax		# 1 (logical shift of negative value)
	shlq $63,%rax		# 0x8000000000000000
	movq %rax,%xmm0		# -0.0
	# fallthrough
.Ltrunc_sac:
	movabs $0x3ff0000000000000,%rax	# 1.0
	movq %rax,%xmm1
	movq %rcx,%xmm2
	addsd %xmm2,%xmm1	# sacrificial orig+1.0
	ret
.Ltrunc_arch:
	roundsd $0x0b,%xmm0,%xmm0	# suppress exceptions, round to zero
	ret
	.size trunc,.-trunc

	.globl truncf
	.type truncf,@function
# float truncf(float x) — same design, 32-bit shifts.
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
