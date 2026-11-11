	.text
	.globl simd3_strstr
	.type simd3_strstr,@function
# char *simd3_strstr(const unsigned char *h, const unsigned char *n)
# F8 Phase 2 scratch candidate for 3-byte needles (original Saphira code,
# upstream musl MIT). Replaces threebyte_strstr: same contract.
# Method: 16-byte windows with 14-byte step (2-byte overlap), ordinary
# SSE2 equality masks: hits = eq(n0) & (eq(n1)>>1) & (eq(n2)>>2),
# accepted only for start j <= 13. NUL/page handling as in simd2_strstr:
# 16B loads only when fully mapped; scalar tail uses single-byte reads
# with the generic's fault profile; rsi strictly increases.
# No AVX/VEX anywhere (SSE-only, no clock/transition risk).
# Touches: rax, rcx, rdx, rsi, r8-r10, xmm0-xmm3, xmm5-xmm7. Callee-saved
# registers, DF and stack discipline preserved; integer flags unspecified.
simd3_strstr:
	movzbq (%rsi),%r8	# n0
	movzbq 1(%rsi),%r9	# n1
	movzbq 2(%rsi),%r10	# n2
	mov %r8,%rax
	mov %r9,%rcx
	mov %r10,%rdx
	imul $0x01010101,%eax
	imul $0x01010101,%ecx
	imul $0x01010101,%edx
	movd %eax,%xmm1
	movd %ecx,%xmm2
	movd %edx,%xmm3
	pshufd $0,%xmm1,%xmm1
	pshufd $0,%xmm2,%xmm2
	pshufd $0,%xmm3,%xmm3
	pxor %xmm7,%xmm7
	mov %rdi,%rsi		# rsi = cursor
.Ls3_page:
	mov %rsi,%rax
	and $4095,%rax
	neg %rax
	add $4096,%rax
	cmp $16,%rax
	jb .Ls3_tail
	movdqu (%rsi),%xmm0
	movdqa %xmm0,%xmm5
	movdqa %xmm0,%xmm6
	pcmpeqb %xmm1,%xmm5	# eq(n0)
	pcmpeqb %xmm2,%xmm6	# eq(n1)
	pmovmskb %xmm5,%eax
	pmovmskb %xmm6,%ecx
	shr $1,%ecx
	and %ecx,%eax
	movdqa %xmm0,%xmm5
	pcmpeqb %xmm3,%xmm5	# eq(n2)
	pmovmskb %xmm5,%ecx
	shr $2,%ecx
	and %ecx,%eax
	and $0x3fff,%eax	# starts j <= 13 only
	jnz .Ls3_hit
	pcmpeqb %xmm7,%xmm0
	pmovmskb %xmm0,%edx
	test $0x3fff,%edx
	jnz .Ls3_null
	add $14,%rsi		# overlap step
	jmp .Ls3_page
.Ls3_tail:
	movzbq (%rsi),%rcx
	test %rcx,%rcx
	jz .Ls3_null
	cmp %r8b,%cl
	jne .Ls3_adv
	movzbq 1(%rsi),%rdx
	cmp %r9b,%dl
	jne .Ls3_adv
	movzbq 2(%rsi),%rdx
	cmp %r10b,%dl
	jne .Ls3_adv
	mov %rsi,%rax
	ret
.Ls3_adv:
	inc %rsi
	jmp .Ls3_page
.Ls3_hit:
	bsf %eax,%eax		# j = first hit (0..13)
	pcmpeqb %xmm7,%xmm0
	pmovmskb %xmm0,%edx
	mov %eax,%ecx
	mov $1,%eax
	shl %cl,%eax
	dec %eax
	test %eax,%edx
	jnz .Ls3_null
	lea (%rsi,%rcx,1),%rax
	ret
.Ls3_null:
	xor %eax,%eax
	ret
	.size simd3_strstr,.-simd3_strstr
	.section .note.GNU-stack,"",@progbits
