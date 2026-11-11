	.text
	.globl avx2_ascii_run
	.type avx2_ascii_run,@function
# size_t avx2_ascii_run(const unsigned char *s, size_t maxlen)
# Original Saphira implementation under the upstream musl license (MIT, no change).
# Counts leading bytes that are ASCII *and* non-NUL, stopping at the
# first high-bit byte, the first NUL, or maxlen — whichever comes first.
# NEVER reads outside [s, s+maxlen): scalar head until 32-byte aligned,
# then only aligned 32-byte vector blocks (an aligned block cannot
# cross a page, and every loaded block is covered by maxlen), then a
# scalar tail. maxlen==0 performs no read at all.
# Caller contract: use for bounded spans only (e.g. min(wn, page bytes)).
# NUL handling, wn accounting and multibyte decoding stay with the caller.
# Preserves DF; integer flags unspecified on return (musl convention);
# callee-saved registers untouched.
# rdi=s (preserved), rsi=maxlen, rax=count, rdx=cursor, rcx=scratch.
avx2_ascii_run:
	xor %eax,%eax		# count = 0
	mov %rdi,%rdx		# cursor = s
	test %rsi,%rsi
	jz .Lrun_done		# maxlen==0: no read, return 0
	# scalar head to 32-byte alignment (also covers tiny maxlen)
.Lrun_head:
	cmp %rsi,%rax		# count >= maxlen?
	jae .Lrun_done
	test $31,%edx
	jz .Lrun_vectest	# aligned -> try vector path
	movzbq (%rdx),%rcx	# load byte (in-bounds: count < maxlen)
	test $0x80,%cl
	jnz .Lrun_done		# non-ASCII (incl. NUL? no: NUL check below)
	test %rcx,%rcx
	jz .Lrun_done		# NUL -> stop (not counted)
	inc %rdx
	inc %rax
	jmp .Lrun_head
.Lrun_vectest:
	# remaining = maxlen - count; need >= 32 for a vector block
	mov %rsi,%rcx
	sub %rax,%rcx
	cmp $32,%rcx
	jb .Lrun_tail		# <32 left -> scalar tail
	vmovdqa (%rdx),%ymm0	# aligned: cannot cross a page
	vpxor %ymm1,%ymm1,%ymm1	# zero vector (kept in-loop for clarity)
	vpcmpeqb %ymm1,%ymm0,%ymm2	# zeros -> 0xFF bytes
	vpmovmskb %ymm0,%ecx	# hi = high-bit mask
	vpmovmskb %ymm2,%r8d	# zo = NUL mask... (r8d: caller-saved, free)
	or %r8d,%ecx		# stop = non-ASCII or NUL
	jz .Lrun_full		# no stop in this block
	tzcntl %ecx,%ecx	# first stop position
	add %rcx,%rax
	jmp .Lrun_done		# span ends here (cursor NOT advanced past stop)
.Lrun_full:
	add $32,%rdx		# consume full block
	add $32,%rax
	jmp .Lrun_vectest
.Lrun_tail:			# scalar to maxlen (no align requirement)
	cmp %rsi,%rax
	jae .Lrun_done
	movzbq (%rdx),%rcx	# in-bounds: count < maxlen
	test $0x80,%cl
	jnz .Lrun_done
	test %rcx,%rcx
	jz .Lrun_done
	inc %rdx
	inc %rax
	jmp .Lrun_tail
.Lrun_done:
	vzeroupper
	ret
	.size avx2_ascii_run,.-avx2_ascii_run
	.section .note.GNU-stack,"",@progbits
