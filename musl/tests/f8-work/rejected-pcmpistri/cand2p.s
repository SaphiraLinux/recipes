	.text
	.globl simd2p_strstr
	.type simd2p_strstr,@function
# char *simd2p_strstr(const unsigned char *h, const unsigned char *n)
# F8 Phase 2 scratch candidate for 2-byte needles, SSE4.2 pcmpistri
# variant (original Saphira code, upstream musl MIT). Same contract as
# simd2_strstr. Method: implicit-length pcmpistri EQUAL_ORDERED per
# 16-byte window with 15-byte step. Needle {n0,n1} loaded scalarly into
# xmm1 (implicit length 2 via the zeroed upper bytes); haystack is the
# r/m operand. CF=1: ECX holds the first match index (always fully
# before any NUL: implicit lengths restrict matching to valid bytes, and
# needle bytes are nonzero). CF=0: ZF=1 means a NUL lies in the window
# (search ends); ZF=0 advances. Page safety: the 16B window load inside
# pcmpistri executes only when fully mapped; the scalar tail uses
# single-byte reads with the generic's fault profile.
# No AVX/VEX anywhere (SSE-only, no clock/transition risk).
# Touches: rax, rcx, rsi, r8, r9, xmm1. Callee-saved regs, DF and stack
# preserved; ECX/EFLAGS consumed immediately as produced.
simd2p_strstr:
	movzbq (%rsi),%r8	# n0 (scalar tail)
	movzbq 1(%rsi),%r9	# n1 (scalar tail)
	movzwl (%rsi),%eax
	movd %eax,%xmm1		# needle {n0,n1,0,...}: implicit len 2
	mov %rdi,%rsi
.Lp2_page:
	mov %rsi,%rax
	and $4095,%rax
	neg %rax
	add $4096,%rax
	cmp $16,%rax
	jb .Lp2_tail
	pcmpistri $0x08,(%rsi),%xmm1	# CF=match(ECX=idx) ZF=NUL-in-window
	jc .Lp2_hit
	jz .Lp2_null
	add $15,%rsi
	jmp .Lp2_page
.Lp2_tail:
	movzbq (%rsi),%rcx
	test %rcx,%rcx
	jz .Lp2_null
	cmp %r8b,%cl
	jne .Lp2_adv
	movzbq 1(%rsi),%rdx
	cmp %r9b,%dl
	jne .Lp2_adv
	mov %rsi,%rax
	ret
.Lp2_adv:
	inc %rsi
	jmp .Lp2_page
.Lp2_hit:
	lea (%rsi,%rcx,1),%rax	# ECX zero-extends to RCX
	ret
.Lp2_null:
	xor %eax,%eax
	ret
	.size simd2p_strstr,.-simd2p_strstr
	.section .note.GNU-stack,"",@progbits
