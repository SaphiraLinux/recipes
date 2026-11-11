	.text
	.globl simd4_strstr
	.type simd4_strstr,@function
# char *simd4_strstr(const unsigned char *h, const unsigned char *n)
# F8 Phase 2 scratch candidate for 4-byte needles (original Saphira code,
# upstream musl MIT). Replaces fourbyte_strstr: same contract.
# Method: 16-byte windows with 13-byte step (3-byte overlap), ordinary
# SSE2 equality masks: eq(n0) & (eq(n1)>>1) & (eq(n2)>>2) & (eq(n3)>>3),
# accepted only for start j <= 12. NUL/page handling as in simd2_strstr.
# No AVX/VEX anywhere (SSE-only, no clock/transition risk).
# Touches: rax, rcx, rdx, rsi, r8-r11, xmm0-xmm6 (xmm7 zero). Callee-saved
# registers, DF and stack discipline preserved; integer flags unspecified.
simd4_strstr:
	movzbq (%rsi),%r8	# n0
	movzbq 1(%rsi),%r9	# n1
	movzbq 2(%rsi),%r10	# n2
	movzbq 3(%rsi),%r11	# n3
	mov %r8,%rax
	mov %r9,%rcx
	imul $0x01010101,%eax
	imul $0x01010101,%ecx
	movd %eax,%xmm1
	movd %ecx,%xmm2
	mov %r10,%rax
	mov %r11,%rcx
	imul $0x01010101,%eax
	imul $0x01010101,%ecx
	movd %eax,%xmm3
	movd %ecx,%xmm4
	pshufd $0,%xmm1,%xmm1
	pshufd $0,%xmm2,%xmm2
	pshufd $0,%xmm3,%xmm3
	pshufd $0,%xmm4,%xmm4
	pxor %xmm7,%xmm7
	mov %rdi,%rsi		# rsi = cursor
.Ls4_page:
	mov %rsi,%rax
	and $4095,%rax
	neg %rax
	add $4096,%rax
	cmp $16,%rax
	jb .Ls4_tail
	movdqu (%rsi),%xmm0
	movdqa %xmm0,%xmm5
	movdqa %xmm0,%xmm6
	pcmpeqb %xmm1,%xmm5
	pcmpeqb %xmm2,%xmm6
	pmovmskb %xmm5,%eax
	pmovmskb %xmm6,%ecx
	shr $1,%ecx
	and %ecx,%eax
	movdqa %xmm0,%xmm5
	pcmpeqb %xmm3,%xmm5
	pmovmskb %xmm5,%ecx
	shr $2,%ecx
	and %ecx,%eax
	movdqa %xmm0,%xmm5
	pcmpeqb %xmm4,%xmm5
	pmovmskb %xmm5,%ecx
	shr $3,%ecx
	and %ecx,%eax
	and $0x1fff,%eax	# starts j <= 12 only
	jnz .Ls4_hit
	pcmpeqb %xmm7,%xmm0
	pmovmskb %xmm0,%edx
	test $0x1fff,%edx
	jnz .Ls4_null
	add $13,%rsi		# overlap step
	jmp .Ls4_page
.Ls4_tail:
	movzbq (%rsi),%rcx
	test %rcx,%rcx
	jz .Ls4_null
	cmp %r8b,%cl
	jne .Ls4_adv
	movzbq 1(%rsi),%rdx
	cmp %r9b,%dl
	jne .Ls4_adv
	movzbq 2(%rsi),%rdx
	cmp %r10b,%dl
	jne .Ls4_adv
	movzbq 3(%rsi),%rdx
	cmp %r11b,%dl
	jne .Ls4_adv
	mov %rsi,%rax
	ret
.Ls4_adv:
	inc %rsi
	jmp .Ls4_page
.Ls4_hit:
	bsf %eax,%eax		# j = first hit (0..12)
	pcmpeqb %xmm7,%xmm0
	pmovmskb %xmm0,%edx
	mov %eax,%ecx
	mov $1,%eax
	shl %cl,%eax
	dec %eax
	test %eax,%edx
	jnz .Ls4_null
	lea (%rsi,%rcx,1),%rax
	ret
.Ls4_null:
	xor %eax,%eax
	ret
	.size simd4_strstr,.-simd4_strstr
	.section .note.GNU-stack,"",@progbits
