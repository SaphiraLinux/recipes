	.text
	.globl avx2_ascii_span
	.type avx2_ascii_span,@function
# size_t avx2_ascii_span(const unsigned char *s, size_t maxlen)
# Original Saphira implementation under the upstream musl license (MIT, no change). x86-64-v3 (AVX2 + BMI1).
# Returns the count of leading bytes with the high bit clear, within
# [0, maxlen]. NUL (0x00) counts as ASCII: the caller owns termination.
# NEVER reads outside [s, s+maxlen): scalar head until 32-byte aligned,
# aligned 32-byte vector blocks only (an aligned 32-byte load cannot
# cross a page), scalar tail. (Rationale: page safety without masked
# loads and without relying on over-read-tolerant callers.)
# Hot path: vector loop is vmovdqa + vpmovmskb + test/jcc (4 uops).
# Preserves DF; integer flags unspecified on return (musl convention);
# callee-saved untouched; vzeroupper before every return.
# rdi=s (preserved), rsi=maxlen, rax=count, rdx=cursor, r8=end.
avx2_ascii_span:
	xor %eax,%eax		# count = 0
	mov %rdi,%rdx		# cursor = s
	lea (%rdi,%rsi),%r8	# end = s+maxlen
	jmp .Lspan_headtest
.Lspan_head:
	cmp %r8,%rdx		# cursor >= end?
	jae .Lspan_done
	test $31,%edx		# 32-byte aligned?
	jz .Lspan_vectest	# yes -> try vector path
	testb $0x80,(%rdx)	# high bit set?
	jnz .Lspan_done		# non-ASCII -> span ends here
	inc %rdx		# advance cursor
	inc %rax		# count++
.Lspan_headtest:
	cmp %r8,%rdx
	jb .Lspan_headtest2
	jmp .Lspan_done
.Lspan_headtest2:
	test $31,%edx
	jnz .Lspan_head
	# fallthrough to vector test when aligned
.Lspan_vectest:
	mov %r8,%rcx
	sub %rdx,%rcx		# remaining = end - cursor
	cmp $32,%rcx
	jb .Lspan_tail		# <32 left -> scalar tail
	vmovdqa (%rdx),%ymm0	# aligned: cannot cross a page
	vpmovmskb %ymm0,%ecx	# bit set iff byte has high bit
	testl %ecx,%ecx
	jnz .Lspan_partial	# some non-ASCII in this block
	add $32,%rdx		# whole block ASCII
	add $32,%rax
	jmp .Lspan_vectest
.Lspan_partial:
	tzcntl %ecx,%ecx	# index of first non-ASCII byte (mask != 0)
	add %rcx,%rax		# count += index (cursor stays: span ends here)
	jmp .Lspan_done
.Lspan_tail:			# scalar to end (no align requirement)
	cmp %r8,%rdx
	jae .Lspan_done
	testb $0x80,(%rdx)
	jnz .Lspan_done
	inc %rdx
	inc %rax
	jmp .Lspan_tail
.Lspan_done:
	vzeroupper
	ret
	.size avx2_ascii_span,.-avx2_ascii_span
	.section .note.GNU-stack,"",@progbits
