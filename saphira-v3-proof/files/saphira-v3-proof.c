#define _POSIX_C_SOURCE 200809L

#include <immintrin.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#if !defined(__AVX2__) || !defined(__FMA__) || \
    !defined(__BMI__) || !defined(__BMI2__) || \
    !defined(__F16C__) || !defined(__LZCNT__)
#error "Compile this with -march=x86-64-v3"
#endif

#define PI_DIGITS 5000
#define EXPECTED_PI_FNV UINT64_C(0x298a6bbba21caa86)
#define EXPECTED_V3_SIG UINT64_C(0x20c200109d628d04)

#define ARRAY_ELEMENTS (8u * 1024u * 1024u)
#define DEFAULT_PASSES 48u
#define MAX_THREADS 64u

typedef struct {
    const double *a;
    const double *b;
    const double *c;
    size_t begin;
    size_t end;
    unsigned passes;
    double checksum;
} worker_ctx;

static double seconds(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }

    return (double)ts.tv_sec + (double)ts.tv_nsec * 1.0e-9;
}

static uint64_t fnv1a64(const char *s, size_t len)
{
    uint64_t h = UINT64_C(1469598103934665603);

    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)s[i];
        h *= UINT64_C(1099511628211);
    }

    return h;
}

static int runtime_v3_ok(void)
{
    __builtin_cpu_init();

    if (!__builtin_cpu_supports("avx")) {
        return 0;
    }

    if (!__builtin_cpu_supports("avx2")) {
        return 0;
    }

    if (!__builtin_cpu_supports("fma")) {
        return 0;
    }

    if (!__builtin_cpu_supports("bmi")) {
        return 0;
    }

    if (!__builtin_cpu_supports("bmi2")) {
        return 0;
    }

    if (!__builtin_cpu_supports("f16c")) {
        return 0;
    }

    if (!__builtin_cpu_supports("lzcnt")) {
        return 0;
    }

    return 1;
}

static uint64_t v3_probe(void)
{
    const __m256d a = _mm256_set_pd(8.0, 4.0, 2.0, 1.0);
    const __m256d b = _mm256_set1_pd(1.5);
    const __m256d c = _mm256_set1_pd(0.25);

    const __m256d f = _mm256_fmadd_pd(a, b, c);

    const __m256i x =
        _mm256_set_epi32(8, 7, 6, 5, 4, 3, 2, 1);

    const __m256i y =
        _mm256_set1_epi32(17);

    const __m256i m =
        _mm256_mullo_epi32(x, y);

    double fd[4];
    uint32_t md[8];

    uint64_t sig = 0;
    uint64_t pdep;
    uint64_t pext;
    unsigned short half;

    _mm256_storeu_pd(fd, f);
    _mm256_storeu_si256((__m256i *)(void *)md, m);

    pdep = _pdep_u64(
        UINT64_C(0x55aa),
        UINT64_C(0x0f0f0f0f0f0f0f0f));

    pext = _pext_u64(
        UINT64_C(0xf0f00f0ff00ff00f),
        UINT64_C(0x3333333333333333));

    half = _cvtss_sh(1.5f, 0);

    memcpy(&sig, &fd[0], sizeof(sig));

    sig ^= ((uint64_t)md[0] << 32) ^ md[7];
    sig ^= pdep;
    sig ^= pext << 1;
    sig ^= (uint64_t)_lzcnt_u64(
        UINT64_C(0x0000000100000000)) << 56;
    sig ^= (uint64_t)half << 40;

    _mm256_zeroupper();

    return sig;
}

static char *pi_spigot(size_t digits)
{
    size_t len = digits * 10u / 3u + 1u;

    int *a = malloc(len * sizeof(*a));
    char *raw = malloc(digits + 64u);
    char *out = malloc(digits + 1u);

    size_t pos = 0;
    int nines = 0;
    int predigit = 0;

    if ((a == NULL) || (raw == NULL) || (out == NULL)) {
        free(a);
        free(raw);
        free(out);
        return NULL;
    }

    for (size_t i = 0; i < len; i++) {
        a[i] = 2;
    }

    for (size_t j = 0; j < digits; j++) {
        int q = 0;

        for (size_t i = len; i > 0; i--) {
            int ii = (int)i;
            int x = 10 * a[i - 1u] + q * ii;
            int d = 2 * ii - 1;

            a[i - 1u] = x % d;
            q = x / d;
        }

        a[0] = q % 10;
        q /= 10;

        if (q == 9) {
            nines++;
        } else if (q == 10) {
            raw[pos++] = (char)('0' + predigit + 1);

            for (int k = 0; k < nines; k++) {
                raw[pos++] = '0';
            }

            predigit = 0;
            nines = 0;
        } else {
            raw[pos++] = (char)('0' + predigit);
            predigit = q;

            for (int k = 0; k < nines; k++) {
                raw[pos++] = '9';
            }

            nines = 0;
        }
    }

    raw[pos++] = (char)('0' + predigit);

    if ((pos < digits + 1u) || (raw[0] != '0')) {
        free(a);
        free(raw);
        free(out);
        return NULL;
    }

    memcpy(out, raw + 1, digits);
    out[digits] = '\0';

    free(a);
    free(raw);

    return out;
}

static void *simd_worker(void *arg)
{
    worker_ctx *ctx = arg;

    __m256d acc0 = _mm256_setzero_pd();
    __m256d acc1 = _mm256_setzero_pd();

    const __m256d k0 =
        _mm256_set1_pd(0.9999999997);

    const __m256d k1 =
        _mm256_set1_pd(0.0000000003);

    size_t vector_end =
        ctx->begin +
        ((ctx->end - ctx->begin) & ~(size_t)7u);

    for (unsigned pass = 0;
         pass < ctx->passes;
         pass++) {

        for (size_t i = ctx->begin;
             i < vector_end;
             i += 8u) {

            __m256d a0 =
                _mm256_loadu_pd(ctx->a + i);

            __m256d b0 =
                _mm256_loadu_pd(ctx->b + i);

            __m256d c0 =
                _mm256_loadu_pd(ctx->c + i);

            __m256d a1 =
                _mm256_loadu_pd(ctx->a + i + 4u);

            __m256d b1 =
                _mm256_loadu_pd(ctx->b + i + 4u);

            __m256d c1 =
                _mm256_loadu_pd(ctx->c + i + 4u);

            __m256d v0 =
                _mm256_fmadd_pd(a0, b0, c0);

            __m256d v1 =
                _mm256_fmadd_pd(a1, b1, c1);

            v0 = _mm256_fmadd_pd(v0, k0, k1);
            v1 = _mm256_fmadd_pd(v1, k0, k1);

            v0 = _mm256_fmadd_pd(v0, k0, k1);
            v1 = _mm256_fmadd_pd(v1, k0, k1);

            v0 = _mm256_fmadd_pd(v0, k0, k1);
            v1 = _mm256_fmadd_pd(v1, k0, k1);

            acc0 = _mm256_add_pd(acc0, v0);
            acc1 = _mm256_add_pd(acc1, v1);
        }
    }

    {
        double tmp[4];

        __m256d sum =
            _mm256_add_pd(acc0, acc1);

        _mm256_storeu_pd(tmp, sum);

        ctx->checksum =
            tmp[0] + tmp[1] + tmp[2] + tmp[3];
    }

    for (size_t i = vector_end;
         i < ctx->end;
         i++) {

        ctx->checksum +=
            ctx->a[i] * ctx->b[i] + ctx->c[i];
    }

    _mm256_zeroupper();

    return NULL;
}

static int run_stress(unsigned passes)
{
    long online =
        sysconf(_SC_NPROCESSORS_ONLN);

    unsigned threads;

    const size_t n =
        ARRAY_ELEMENTS;

    double *a =
        malloc(n * sizeof(*a));

    double *b =
        malloc(n * sizeof(*b));

    double *c =
        malloc(n * sizeof(*c));

    if (online < 1) {
        online = 1;
    }

    threads = (unsigned)online;

    if (threads > MAX_THREADS) {
        threads = MAX_THREADS;
    }

    pthread_t *ids =
        calloc(threads, sizeof(*ids));

    worker_ctx *ctx =
        calloc(threads, sizeof(*ctx));

    if ((a == NULL) ||
        (b == NULL) ||
        (c == NULL) ||
        (ids == NULL) ||
        (ctx == NULL)) {

        fprintf(stderr, "allocation failed\n");
        return 0;
    }

    for (size_t i = 0; i < n; i++) {
        a[i] =
            1.0 + (double)(i % 1009u) * 1.0e-6;

        b[i] =
            0.5 + (double)(i % 1013u) * 1.0e-6;

        c[i] =
            0.25 + (double)(i % 1019u) * 1.0e-7;
    }

    double start = seconds();

    for (unsigned t = 0;
         t < threads;
         t++) {

        ctx[t].a = a;
        ctx[t].b = b;
        ctx[t].c = c;

        ctx[t].begin =
            (n * t) / threads;

        ctx[t].end =
            (n * (t + 1u)) / threads;

        ctx[t].passes = passes;

        if (pthread_create(
                &ids[t],
                NULL,
                simd_worker,
                &ctx[t]) != 0) {

            perror("pthread_create");
            exit(EXIT_FAILURE);
        }
    }

    double checksum = 0.0;

    for (unsigned t = 0;
         t < threads;
         t++) {

        if (pthread_join(ids[t], NULL) != 0) {
            perror("pthread_join");
            exit(EXIT_FAILURE);
        }

        checksum += ctx[t].checksum;
    }

    double end = seconds();

    double gib =
        ((double)n *
         3.0 *
         sizeof(double) *
         (double)passes) /
        (1024.0 * 1024.0 * 1024.0);

    printf(
        "AVX2/FMA stress : %u threads\n"
        "                   %u passes\n"
        "                   %.2f GiB logical reads\n"
        "                   %.3f seconds\n"
        "                   %.2f GiB/s\n",
        threads,
        passes,
        gib,
        end - start,
        gib / (end - start));

    printf(
        "SIMD checksum    : %.17g\n",
        checksum);

    free(a);
    free(b);
    free(c);
    free(ids);
    free(ctx);

    return 1;
}

int main(int argc, char **argv)
{
    unsigned passes =
        DEFAULT_PASSES;

    if (argc > 1) {
        char *end = NULL;

        unsigned long value =
            strtoul(argv[1], &end, 10);

        if ((end == argv[1]) ||
            (*end != '\0') ||
            (value == 0) ||
            (value > 2097152ul)) {

            fprintf(
                stderr,
                "usage: %s [stress-passes]\n",
                argv[0]);

            return EXIT_FAILURE;
        }

        passes = (unsigned)value;
    }

    puts(
        "Saphira Genesis x86-64-v3 validation\n"
        "====================================");

    if (!runtime_v3_ok()) {
        fprintf(
            stderr,
            "FAIL: runtime CPU does not expose "
            "required x86-64-v3 features\n");

        return EXIT_FAILURE;
    }

    uint64_t probe = v3_probe();

    printf(
        "x86-64-v3 probe : "
        "AVX2/FMA/BMI2/F16C/LZCNT executed\n");

    printf(
        "probe signature : %016llx [%s]\n",
        (unsigned long long)probe,
        probe == EXPECTED_V3_SIG
            ? "PASS"
            : "FAIL");

    if (probe != EXPECTED_V3_SIG) {
        return EXIT_FAILURE;
    }

    double start = seconds();

    char *pi =
        pi_spigot(PI_DIGITS);

    double end = seconds();

    if (pi == NULL) {
        fprintf(stderr, "FAIL: pi calculation\n");
        return EXIT_FAILURE;
    }

    uint64_t hash =
        fnv1a64(pi, PI_DIGITS);

    printf(
        "pi digits       : %d in %.3f seconds\n",
        PI_DIGITS,
        end - start);

    printf(
        "pi first 64     : %.64s\n",
        pi);

    printf(
        "pi last 64      : %.64s\n",
        pi + PI_DIGITS - 64);

    printf(
        "pi FNV-1a/64    : %016llx [%s]\n",
        (unsigned long long)hash,
        hash == EXPECTED_PI_FNV
            ? "PASS"
            : "FAIL");

    free(pi);

    if (hash != EXPECTED_PI_FNV) {
        return EXIT_FAILURE;
    }

    if (!run_stress(passes)) {
        return EXIT_FAILURE;
    }

    puts(
        "RESULT           : PASS\n"
        "compiler + libc + pthreads + "
        "x86-64-v3 execution validated");

    return EXIT_SUCCESS;
}
