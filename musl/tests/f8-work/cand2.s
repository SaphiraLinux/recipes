	.text
	.globl simd2_strstr
	.type simd2_strstr,@function
# char *simd2_strstr(const unsigned char *h, const unsigned char *n)
# F8 Phase 2 scratch candidate for 2-byte needles (original Saphira code,
# upstream musl MIT). Replaces twobyte_strstr: same contract (first match
# address, NUL-terminated haystack, NULL if none).
# Method: 16-byte windows with 15-byte step (1-byte overlap), ordinary
# SSE2 equality masks: hits = eq(n0) & (eq(n1) >> 1), accepted only for
# start j <= 14. NUL handling: zero-mask check; a hit preceded by NUL or
# a NUL inside the accepted start range with no hit ends the search.
# Page safety: a 16-byte vector load executes only when all 16 bytes are
# mapped (page_bytes >= 16). All other reads are single bytes exactly
# where the generic shift loop would also read (same fault profile).
# Coverage is gap-free: vector chunks overlap by m-1 and the scalar loop
# advances byte by byte; rsi strictly increases, so termination matches
# the generic (NUL stop, or a fault on invalid unterminated input).
# No AVX/VEX anywhere (SSE-only, no clock/transition risk).
# Touches: rax, rcx, rdx, rsi, r8, r9, xmm0-xmm2, xmm5-xmm7. Callee-saved
# registers, DF and stack discipline preserved; integer flags unspecified.
simd2_strstr:
	movzbq (%rsi),%r8	# n0 (kept for scalar tail)
	movzbq 1(%rsi),%r9	# n1 (kept for scalar tail)
	mov %r8,%rax
	mov %r9,%rcx
	imul $0x01010101,%eax
	imul $0x01010101,%ecx
	movd %eax,%xmm1
	movd %ecx,%xmm2
	pshufd $0,%xmm1,%xmm1	# broadcast n0
	pshufd $0,%xmm2,%xmm2	# broadcast n1
	pxor %xmm7,%xmm7		# zero
	mov %rdi,%rsi		# rsi = cursor (n no longer needed)
.Ls2_page:
	mov %rsi,%rax
	and $4095,%rax
	neg %rax
	add $4096,%rax		# rax = bytes to page end (1..4096)
	cmp $16,%rax
	jb .Ls2_tail
	movdqu (%rsi),%xmm0	# 16B load, fully mapped
	movdqa %xmm0,%xmm5
	movdqa %xmm0,%xmm6
	pcmpeqb %xmm1,%xmm5	# eq(n0)
	pcmpeqb %xmm2,%xmm6	# eq(n1)
	pmovmskb %xmm5,%eax
	pmovmskb %xmm6,%ecx
	shr $1,%ecx
	and %ecx,%eax
	and $0x7fff,%eax	# starts j <= 14 only
	jnz .Ls2_hit
	pcmpeqb %xmm7,%xmm0	# zero mask for NUL-stop
	pmovmskb %xmm0,%edx
	test $0x7fff,%edx	# NUL in accepted range?
	jnz .Ls2_null
	add $15,%rsi		# overlap step
	jmp .Ls2_page
.Ls2_tail:
	# single-byte reads only: same fault profile as generic
	movzbq (%rsi),%rcx
	test %rcx,%rcx
	jz .Ls2_null
	cmp %r8b,%cl
	jne .Ls2_adv
	movzbq 1(%rsi),%rdx	# generic reads this byte too
	cmp %r9b,%dl
	jne .Ls2_adv
	mov %rsi,%rax		# match
	ret
.Ls2_adv:
	inc %rsi
	jmp .Ls2_page
.Ls2_hit:
	bsf %eax,%eax		# j = first hit (0..14)
	pcmpeqb %xmm7,%xmm0
	pmovmskb %xmm0,%edx
	mov %eax,%ecx		# j for lea
	mov $1,%eax
	shl %cl,%eax		# 1<<j (j<=14, exact)
	dec %eax		# (1<<j)-1
	test %eax,%edx		# NUL before match?
	jnz .Ls2_null
	lea (%rsi,%rcx,1),%rax	# h + j
	ret
.Ls2_null:
	xor %eax,%eax
	ret
	.size simd2_strstr,.-simd2_strstr
	.section .note.GNU-stack,"",@progbits
