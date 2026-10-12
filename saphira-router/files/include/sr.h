/* sr.h -- common types and helpers for saphira-router core. */

#ifndef SR_H
#define SR_H

#include <stddef.h>
#include <stdint.h>

/* Exit / status codes. These are part of the CLI contract (D9 section 4):
 * denied, failed and partial MUST be distinguishable by a script. */
enum {
    SR_OK          = 0,
    SR_ERR_FAILED  = 1,   /* the operation ran and failed        */
    SR_ERR_DENIED  = 2,   /* authorization refused it (D5 6)    */
    SR_ERR_PARTIAL = 3,   /* multi-target: some succeeded (D8 6) */
    SR_ERR_USAGE   = 4,
    SR_ERR_UNAVAILABLE = 5 /* a capability/feature is not usable (D6 3) */
};

#define SR_MAX_ID 64
#define SR_MAX_NAME 128
#define SR_MAX_PATH 512
#define SR_MAX_TEXT 4096
#define SR_MAX_JSON (1 << 20)

/* Log levels, routed into the event system. */
enum { SR_LOG_ERROR = 0, SR_LOG_WARN = 1, SR_LOG_INFO = 2, SR_LOG_DEBUG = 3 };

void sr_log(int level, const char *fmt, ...);
void sr_log_set_level(int level);

/* strdup that aborts on OOM -- used only where failure is genuinely fatal. */
char *sr_xstrdup(const char *s);

/* Trim ASCII whitespace in place. Returns s. */
char *sr_trim(char *s);

/* Case-insensitive compare. */
int sr_strcaseeq(const char *a, const char *b);

/* Read a whole file into a NUL-terminated malloc'd buffer. Returns 0/-1. */
int sr_read_file(const char *path, char **out, size_t *out_len);

/* Write a buffer to path atomically (write temp, fsync, rename). */
int sr_write_file_atomic(const char *path, const char *data, size_t len,
                         unsigned mode);

/* Generate a random id. Aborts on failure. */
void sr_gen_id(char *out, size_t outsz);

#endif /* SR_H */
