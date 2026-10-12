/*
 * saphira-bridge - configuration.
 * BUSL-1.1, see LICENSE.
 *
 * Deliberately small: which ports, how long an address may sit idle, and how
 * many addresses may be held. A lab instrument with a large configuration
 * language is a lab instrument nobody reads before wiring it up wrong.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

#include "bridge.h"

void br_log_msg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
    fputc('\n', stdout);
    fflush(stdout);
}

void br_log_err(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "saphira-bridge: ");
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    fflush(stderr);
}

int br_name_is_valid(const char *s) {
    if (!s || !*s) return 0;
    size_t n = strlen(s);
    if (n >= BR_IFNAME_MAX) return 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (!isalnum(c) && c != '-' && c != '_' && c != '.') return 0;
    }
    return 1;
}

static int parse_int(const char *v, int lo, int hi, int *out) {
    char *end = NULL;
    long n = strtol(v, &end, 10);
    if (!v || *v == '\0' || !end || *end != '\0') return -1;
    if (n < lo || n > hi) return -1;
    *out = (int)n;
    return 0;
}

static char *trim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) e--;
    *e = '\0';
    return s;
}

/* Split "key=value" in place. Returns 0 on success. */
static int split_kv(char *tok, char **k, char **v) {
    char *eq = strchr(tok, '=');
    if (!eq) return -1;
    *eq = '\0';
    *k = trim(tok);
    *v = trim(eq + 1);
    return (**k ? 0 : -1);
}

int br_config_load(const char *path, struct br_config *cfg, const char *name) {
    FILE *f;
    char line[512];
    int lineno = 0;

    memset(cfg, 0, sizeof(*cfg));
    cfg->age_secs = 300;      /* the Linux bridge default */
    cfg->max_entries = 4096;
    cfg->promiscuous = 1;
    /* Kernel-side suppression of our own transmissions is preferred, with the
     * sll_pkttype check kept underneath it as a second, independent line. Both
     * are on: one is a performance path, the other is the policy. */
    cfg->ignore_outgoing = 1;
    cfg->sample = 0;
    /* 128, not 127: saphira-udpdist owns 127. A packaged identity must be a
     * fresh reservation, never one already allocated. */
    cfg->drop_user = 128;
    cfg->drop_group = 128;
    snprintf(cfg->svcname, sizeof(cfg->svcname), "%s", name ? name : "saphira-bridge");

    f = fopen(path, "r");
    if (!f) {
        br_log_err("%s: %s", path, strerror(errno));
        return -1;
    }

    while (fgets(line, sizeof(line), f)) {
        char *p = trim(line);
        char *k, *v;
        lineno++;
        if (!*p || *p == '#') continue;

        if (split_kv(p, &k, &v) != 0) {
            br_log_err("%s:%d: expected key=value", path, lineno);
            fclose(f);
            return -1;
        }

        if (strcmp(k, "port") == 0) {
            if (cfg->nports >= BR_MAX_PORTS) {
                br_log_err("%s:%d: at most %d ports", path, lineno, BR_MAX_PORTS);
                fclose(f);
                return -1;
            }
            if (!br_name_is_valid(v)) {
                br_log_err("%s:%d: invalid interface name '%s'", path, lineno, v);
                fclose(f);
                return -1;
            }
            /* A repeated port would make "the port it arrived from" ambiguous
             * and every flood would echo back into the sender. */
            for (int i = 0; i < cfg->nports; i++) {
                if (strcmp(cfg->ports[i].name, v) == 0) {
                    br_log_err("%s:%d: port '%s' is listed twice", path, lineno, v);
                    fclose(f);
                    return -1;
                }
            }
            struct br_port *p = &cfg->ports[cfg->nports];
            memset(p, 0, sizeof(*p));
            snprintf(p->name, sizeof(p->name), "%s", v);
            p->index = cfg->nports;
            p->fd = -1;
            p->tx_fd = -1;
            p->ifindex = -1;
            cfg->nports++;
        } else if (strcmp(k, "age_secs") == 0) {
            if (parse_int(v, 1, 86400, &cfg->age_secs) != 0) {
                br_log_err("%s:%d: age_secs must be 1..86400", path, lineno);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "max_entries") == 0) {
            if (parse_int(v, BR_CAM_MIN, BR_CAM_MAX, &cfg->max_entries) != 0) {
                br_log_err("%s:%d: max_entries must be %d..%d", path, lineno,
                           BR_CAM_MIN, BR_CAM_MAX);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "ignore_outgoing") == 0) {
            if (parse_int(v, 0, 1, &cfg->ignore_outgoing) != 0) {
                br_log_err("%s:%d: ignore_outgoing must be 0 or 1", path, lineno);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "sample") == 0) {
            /* Log every Nth frame with both addresses, the ingress port and
             * the packet type. A bounded spread beats sampling only the first
             * frames, which in a storm are the background rather than the loop. */
            if (parse_int(v, 0, 1000000, &cfg->sample) != 0) {
                br_log_err("%s:%d: sample must be 0..1000000", path, lineno);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "promiscuous") == 0) {
            if (parse_int(v, 0, 1, &cfg->promiscuous) != 0) {
                br_log_err("%s:%d: promiscuous must be 0 or 1", path, lineno);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "uid") == 0) {
            if (parse_int(v, 0, 65535, &cfg->drop_user) != 0) {
                br_log_err("%s:%d: uid must be 0..65535", path, lineno);
                fclose(f);
                return -1;
            }
        } else if (strcmp(k, "gid") == 0) {
            if (parse_int(v, 0, 65535, &cfg->drop_group) != 0) {
                br_log_err("%s:%d: gid must be 0..65535", path, lineno);
                fclose(f);
                return -1;
            }
        } else {
            /* Refusing an unknown key is the point of a small configuration
             * language: a typo must not silently leave a port unbridged. */
            br_log_err("%s:%d: unknown key '%s'", path, lineno, k);
            fclose(f);
            return -1;
        }
    }
    fclose(f);

    if (cfg->nports < 2) {
        br_log_err("%s: at least two ports are required; one port cannot join "
                   "anything to anything", path);
        return -1;
    }
    return 0;
}
