#include <stdio.h>
#include <string.h>
#include <stdint.h>
extern int arch_strncmp(const char *, const char *, size_t);
extern int arch_memcmp(const void *, const void *, size_t);
static int fails = 0, n = 0;
#define CK(g, a) do { n++; if (!!(g) != !!(a) || ((g) && ((g<0)!=(a<0)) && ((g>0)!=(a>0)))) { printf("EDGE-FAIL %s:%d got=%d want=%d\n", __func__, __LINE__, (a), (g)); fails++; } } while (0)
#define CKV(g, a) do { n++; if ((g) != (a)) { printf("EDGE-FAIL %s:%d got=%d want=%d\n", __func__, __LINE__, (a), (g)); fails++; } } while (0)
int main(void) {
    /* first-byte / last-byte diffs, all lengths incl 0/1 */
    for (size_t len = 0; len < 40; len++) {
        static char A[64], B[64];
        for (int i = 0; i < 64; i++) { A[i] = (char)(i + 1); B[i] = (char)(i + 1); }
        CKV(strncmp(A, B, len), arch_strncmp(A, B, len));
        CKV(memcmp(A, B, len), arch_memcmp(A, B, len));
        if (len) { B[0] ^= 0xFF; CKV(strncmp(A, B, len), arch_strncmp(A, B, len)); CKV(memcmp(A, B, len), arch_memcmp(A, B, len)); B[0] ^= 0xFF; }
        if (len) { B[len-1] ^= 0xFF; CKV(strncmp(A, B, len), arch_strncmp(A, B, len)); CKV(memcmp(A, B, len), arch_memcmp(A, B, len)); B[len-1] ^= 0xFF; }
        /* embedded NULs at every position (both / left-only / right-only) */
        for (size_t p = 0; p < len; p++) {
            char sa = A[p], sb = B[p]; A[p] = B[p] = 0;
            CK(strncmp(A, B, len), arch_strncmp(A, B, len)); CK(memcmp(A, B, len), arch_memcmp(A, B, len));
            A[p] = sa; B[p] = sb;
            A[p] = 0; CK(strncmp(A, B, len), arch_strncmp(A, B, len)); CK(memcmp(A, B, len), arch_memcmp(A, B, len)); A[p] = sa;
            B[p] = 0; CK(strncmp(A, B, len), arch_strncmp(A, B, len)); CK(memcmp(A, B, len), arch_memcmp(A, B, len)); B[p] = sb;
        }
        /* unsigned extremes */
        memset(A, 0xFF, 64); memset(B, 0xFF, 64); CKV(strncmp(A, B, len), arch_strncmp(A, B, len)); CKV(memcmp(A, B, len), arch_memcmp(A, B, len));
        memset(A, 0x00, 64); memset(B, 0xFF, 64); CKV(strncmp(A, B, len), arch_strncmp(A, B, len)); CKV(memcmp(A, B, len), arch_memcmp(A, B, len));
        memset(A, 0x80, 64); memset(B, 0x7F, 64); CKV(strncmp(A, B, len), arch_strncmp(A, B, len)); CKV(memcmp(A, B, len), arch_memcmp(A, B, len));
        /* matching prefixes then differ at end */
        memset(A, 'x', 64); memset(B, 'x', 64);
        if (len) { A[len-1] = 'y'; CK(strncmp(A, B, len), arch_strncmp(A, B, len)); CK(memcmp(A, B, len), arch_memcmp(A, B, len)); }
    }
    printf("EDGE checked=%d fails=%d\n", n, fails);
    return fails != 0;
}
