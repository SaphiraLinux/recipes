/* SSE2 sketch candidates for byte-loop string funcs (scratch-only).
 * Page-safe: 16B loads only when the block stays in-page. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <emmintrin.h>

static int page_ok(const void *p) { return ((uintptr_t)p & 0xFFF) <= 0xFF0; }

int sk_strncmp(const char *l, const char *r, size_t n)
{
	if (!n) return 0;
	/* word-at-a-time while both 16B blocks stay in-page and n allows */
	while (n >= 16 && page_ok(l) && page_ok(r)) {
		__m128i a = _mm_loadu_si128((const __m128i *)l);
		__m128i b = _mm_loadu_si128((const __m128i *)r);
		unsigned eq = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(a, b));
		unsigned za = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(a, _mm_setzero_si128()));
		unsigned zb = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(b, _mm_setzero_si128()));
		unsigned stop = (~eq | za | zb) & 0xFFFFu;
		if (stop) {
			unsigned i = (unsigned)__builtin_ctz(stop);
			return ((const unsigned char *)l)[i] - ((const unsigned char *)r)[i];
		}
		l += 16; r += 16; n -= 16;
	}
	/* byte tail (also NUL-aware, like generic) */
	if (!n--) return 0;
	for (; *l && *r && n && *l == *r; l++, r++, n--);
	return *(const unsigned char *)l - *(const unsigned char *)r;
}

int sk_memcmp(const void *vl, const void *vr, size_t n)
{
	const unsigned char *l = vl, *r = vr;
	while (n >= 16 && page_ok(l) && page_ok(r)) {
		__m128i a = _mm_loadu_si128((const __m128i *)l);
		__m128i b = _mm_loadu_si128((const __m128i *)r);
		unsigned m = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(a, b));
		if (m != 0xFFFF) {
			unsigned i = __builtin_ctz(~m);
			return l[i] - r[i];
		}
		l += 16; r += 16; n -= 16;
	}
	for (; n && *l == *r; n--, l++, r++);
	return n ? *l - *r : 0;
}

void *sk_memchr(const void *src, int c, size_t n)
{
	const unsigned char *s = src;
	unsigned char cc = (unsigned char)c;
	/* align to 16 without over-read: byte head */
	while (n && ((uintptr_t)s & 15)) {
		if (*s == cc) return (void *)s;
		s++; n--;
	}
	__m128i k = _mm_set1_epi8((char)cc);
	while (n >= 16) {
		/* only load if block is in-page OR tail remains (tail bytes
		 * are always valid when n >= 16 is claimed against a valid
		 * [s, s+n) range... except the last partial block: loads are
		 * exact-16 here so [s,s+16) subset of [s,s+n): valid. But
		 * page crossing needs the NEXT page mapped: check it. */
		if (!page_ok(s)) break;
		__m128i a = _mm_loadu_si128((const __m128i *)s);
		unsigned m = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(a, k));
		if (m) return (void *)(s + __builtin_ctz(m));
		s += 16; n -= 16;
	}
	for (; n && *s != cc; s++, n--);
	return n ? (void *)s : 0;
}
