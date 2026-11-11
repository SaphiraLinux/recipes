	.text
	.globl nearbyint
	.type nearbyint,@function
# double nearbyint(double x) — SSE4.1, DAZ-gated cold path (F4).
# Follows the MXCSR rounding mode; never raises inexact (suppress).
# Hot path (normal x): 4 insns, no MXCSR read, no stack.
# Cold path (zero/subnormal): DAZ=1 -> arch insn (flushed input still
# rounds to the TRUE signed zero, silent like generic); DAZ=0 zero ->
# arch insn (exact, silent); DAZ=0 subnormal -> arch value + ONE
# sacrificial ucomisd orig,0.0: raises DE for the denormal input and
# NOTHING else (no FP result, so never PE/UE/IE, FTZ-independent;
# traps iff DM unmasked). Masked flags then match generic musl
# (which clears PE but keeps DE) bit-for-bit. The UM/PM-trap
# difference vs generic's intermediates is documented, not chased.
# No ldmxcsr anywhere.
nearbyint:
	movq %xmm0,%rax
	addq %rax,%rax		# drop sign; top 11 bits = biased exponent
	shrq $53,%rax		# 0 iff x is ±0 or subnormal
	jnz .Lni_arch
	movq %xmm0,%rcx		# cold entry: save orig bits (cold only)
	movq %rcx,%rax
	addq %rax,%rax
	jz .Lni_arch		# ±0: arch value, exact and silent
	subq $8,%rsp		# subnormal: test DAZ
	stmxcsr (%rsp)
	movl (%rsp),%eax
	addq $8,%rsp
	testl $0x40,%eax	# DAZ?
	jnz .Lni_arch		# DAZ=1: arch value+flags correct
	roundsd $0x0c,%xmm0,%xmm0	# DAZ=0: arch value (exact here)
	xorpd %xmm1,%xmm1	# +0.0
	movq %rcx,%xmm2		# orig bits
	ucomisd %xmm1,%xmm2	# sacrificial: DE iff denormal input, never PE
	ret
.Lni_arch:
	roundsd $0x0c,%xmm0,%xmm0	# MXCSR mode, suppress all
	ret
	.size nearbyint,.-nearbyint
	.section .note.GNU-stack,"",@progbits
