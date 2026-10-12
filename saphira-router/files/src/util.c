/* util.c -- logging, string, file and id helpers. */

#include "sr.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int g_level = SR_LOG_INFO;

void sr_log_set_level(int level) { g_level = level; }

void sr_log(int level, const char *fmt, ...)
{
    if (level > g_level) return;
    static const char *tag[] = { "error", "warn", "info", "debug" };
    char msg[SR_MAX_TEXT];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    fprintf(stderr, "[%s] %s\n", tag[level < 0 ? 0 : (level > 3 ? 3 : level)], msg);
}

char *sr_xstrdup(const char *s)
{
    if (!s) s = "";
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (!p) { fprintf(stderr, "out of memory\n"); abort(); }
    memcpy(p, s, n);
    return p;
}

char *sr_trim(char *s)
{
    if (!s) return s;
    char *p = s;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1])) s[--n] = '\0';
    return s;
}

int sr_strcaseeq(const char *a, const char *b)
{
    if (!a || !b) return a == b;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == *b;
}

int sr_read_file(const char *path, char **out, size_t *out_len)
{
    *out = NULL;
    if (out_len) *out_len = 0;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;

    size_t cap = 8192, len = 0;
    char *buf = malloc(cap);
    if (!buf) { close(fd); return -1; }

    for (;;) {
        if (len + 4096 > cap) {
            size_t ncap = cap * 2;
            char *nb = realloc(buf, ncap);
            if (!nb) { free(buf); close(fd); return -1; }
            buf = nb; cap = ncap;
        }
        ssize_t r = read(fd, buf + len, cap - len - 1);
        if (r < 0) { if (errno == EINTR) continue; free(buf); close(fd); return -1; }
        if (r == 0) break;
        len += (size_t)r;
    }
    close(fd);
    buf[len] = '\0';
    *out = buf;
    if (out_len) *out_len = len;
    return 0;
}

int sr_write_file_atomic(const char *path, const char *data, size_t len,
                         unsigned mode)
{
    char tmp[SR_MAX_PATH];
    snprintf(tmp, sizeof tmp, "%s.tmp.%d", path, (int)getpid());

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
    if (fd < 0) return -1;

    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, data + off, len - off);
        if (w < 0) { if (errno == EINTR) continue; close(fd); unlink(tmp); return -1; }
        off += (size_t)w;
    }
    if (fsync(fd) < 0) { close(fd); unlink(tmp); return -1; }
    if (close(fd) < 0) { unlink(tmp); return -1; }
    if (rename(tmp, path) < 0) { unlink(tmp); return -1; }
    return 0;
}

void sr_gen_id(char *out, size_t outsz)
{
    unsigned char b[16];
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        ssize_t got = 0;
        while (got < (ssize_t)sizeof b) {
            ssize_t r = read(fd, b + got, sizeof b - (size_t)got);
            if (r <= 0) break;
            got += r;
        }
        close(fd);
        if (got != (ssize_t)sizeof b) {
            sr_log(SR_LOG_ERROR, "short read from /dev/urandom");
            abort();
        }
    } else {
        abort();
    }
    /* hex */
    static const char hx[] = "0123456789abcdef";
    size_t o = 0;
    for (size_t i = 0; i < sizeof b && o + 2 < outsz; i++) {
        out[o++] = hx[b[i] >> 4];
        out[o++] = hx[b[i] & 0xf];
    }
    out[o] = '\0';
}
