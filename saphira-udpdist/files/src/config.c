/* saphira-udpdist - configuration parsing and validation. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

#define MAX_TOK 32

static char *trim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    if (*s == '\0') return s;
    char *e = s + strlen(s) - 1;
    while (e > s && isspace((unsigned char)*e)) { *e = '\0'; e--; }
    return s;
}

int name_is_valid(const char *s) {
    if (!s || !*s) return 0;
    for (const char *p = s; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (!isalnum(c) && c != '_' && c != '-') return 0;
    }
    return 1;
}

int iface_index(struct service *svc, const char *name) {
    for (int i = 0; i < svc->nifaces; i++)
        if (strcmp(svc->ifaces[i].name, name) == 0) return i;
    if (svc->nifaces >= UD_MAX_IFACES) return -1;
    int i = svc->nifaces++;
    memset(&svc->ifaces[i], 0, sizeof(svc->ifaces[i]));
    snprintf(svc->ifaces[i].name, UD_IFNAME_MAX, "%s", name);
    svc->ifaces[i].index = -1;
    return i;
}

static int attr_is(const char *tok, const char *k, const char **out) {
    size_t kl = strlen(k);
    if (strncmp(tok, k, kl) != 0) return 0;
    if (tok[kl] != '=') return 0;
    *out = tok + kl + 1;
    return 1;
}

static int parse_backend(struct service *svc, const char *spec, char *tok[], char *err,
                         size_t errlen) {
    if (svc->nbacks >= UD_MAX_BACKENDS) {
        snprintf(err, errlen, "too many backends (max %d)", UD_MAX_BACKENDS);
        return -1;
    }
    struct backend b;
    memset(&b, 0, sizeof(b));
    if (addr_parse_hostport(spec, &b.addr) != 0) {
        snprintf(err, errlen, "invalid backend address '%s' (want addr:port)", spec);
        return -1;
    }
    addr_normalize(&b.addr);
    if (b.addr.port == 0) {
        snprintf(err, errlen, "backend '%s' has port 0", spec);
        return -1;
    }
    if (strlen(spec) >= sizeof(b.id)) {
        snprintf(err, errlen, "backend spec too long");
        return -1;
    }
    for (int i = 1; i < MAX_TOK; i++) {
        const char *v = NULL;
        if (!tok[i]) break;
        if (attr_is(tok[i], "mac", &v)) {
            if (strcmp(v, "auto") == 0) {
                /* Learn the hardware address from the kernel's neighbour table
                 * at startup, and keep following it afterwards. Valid only for
                 * a backend on the same broadcast domain: neighbour resolution
                 * is undefined across a router, and "auto" is a claim that the
                 * operator is asserting sameness, not a promise to succeed. */
                b.mac_learned = 1;
            } else if (mac_parse(v, b.mac) != 0) {
                snprintf(err, errlen, "invalid mac '%s'", v);
                return -1;
            } else {
                b.mac_configured = 1;
            }
        } else if (attr_is(tok[i], "sid", &v)) {
            char *endp = NULL;
            unsigned long long sid = strtoull(v, &endp, 10);
            if (!endp || *endp != '\0') {
                snprintf(err, errlen, "invalid sid '%s'", v);
                return -1;
            }
            b.quic_sid = sid;
            b.quic_sid_set = 1;
        } else {
            snprintf(err, errlen, "unknown backend attribute '%s'", tok[i]);
            return -1;
        }
    }
    addr_id(&b.addr, b.id, sizeof(b.id));
    for (int i = 0; i < svc->nbacks; i++) {
        if (strcmp(svc->backs[i].id, b.id) == 0) {
            snprintf(err, errlen, "duplicate backend '%s'", b.id);
            return -1;
        }
    }
    b.healthy = 1;
    backend_compute_hash(&b);
    svc->backs[svc->nbacks++] = b;
    return 0;
}

static int parse_frontend(struct service *svc, const char *spec, char *tok[], char *err,
                          size_t errlen) {
    if (svc->nfronts >= UD_MAX_FRONTS) {
        snprintf(err, errlen, "too many frontends (max %d)", UD_MAX_FRONTS);
        return -1;
    }
    struct frontend f;
    memset(&f, 0, sizeof(f));
    if (addr_parse_hostport(spec, &f.addr) != 0) {
        snprintf(err, errlen, "invalid frontend address '%s' (want addr:port)", spec);
        return -1;
    }
    addr_normalize(&f.addr);
    if (f.addr.port == 0) {
        snprintf(err, errlen, "frontend '%s' has port 0", spec);
        return -1;
    }
    f.iface = -1;
    f.quic_mode = QUIC_MODE_FALLBACK;
    for (int i = 1; i < MAX_TOK; i++) {
        const char *v = NULL;
        if (!tok[i]) break;
        if (attr_is(tok[i], "iface", &v)) {
            f.iface = iface_index(svc, v);
            if (f.iface < 0) {
                snprintf(err, errlen, "too many interfaces (max %d)", UD_MAX_IFACES);
                return -1;
            }
        } else if (attr_is(tok[i], "proto", &v)) {
            if (strcmp(v, "udp") == 0) f.proto = FRONT_PROTO_UDP;
            else if (strcmp(v, "quic") == 0) f.proto = FRONT_PROTO_QUIC;
            else {
                snprintf(err, errlen, "proto must be udp or quic, got '%s'", v);
                return -1;
            }
        } else if (attr_is(tok[i], "quic_mode", &v)) {
            if (strcmp(v, "fallback") == 0) f.quic_mode = QUIC_MODE_FALLBACK;
            else if (strcmp(v, "quic_lb") == 0) f.quic_mode = QUIC_MODE_QUIC_LB;
            else {
                snprintf(err, errlen, "quic_mode must be fallback or quic_lb, got '%s'", v);
                return -1;
            }
        } else {
            snprintf(err, errlen, "unknown frontend attribute '%s'", tok[i]);
            return -1;
        }
    }
    for (int i = 0; i < svc->nfronts; i++) {
        struct frontend *o = &svc->fronts[i];
        if (o->addr.family == f.addr.family && o->addr.port == f.addr.port &&
            memcmp(o->addr.addr, f.addr.addr,
                   (o->addr.family == AF_INET) ? 4 : 16) == 0) {
            snprintf(err, errlen, "duplicate frontend on the same address and port");
            return -1;
        }
    }
    svc->fronts[svc->nfronts++] = f;
    return 0;
}

int config_load(const char *path, struct service *svc, const char *name) {
    memset(svc, 0, sizeof(*svc));
    svc->max_datagram = MAX_DATAGRAM_DEFAULT;
    snprintf(svc->name, sizeof(svc->name), "%s", name ? name : "udpdist");
    snprintf(svc->config_path, sizeof(svc->config_path), "%s", path);

    FILE *fp = fopen(path, "r");
    if (!fp) {
        fprintf(stderr, "udpdist: cannot open %s: %s\n", path, strerror(errno));
        return -1;
    }

    char line[UD_LINE_MAX];
    char err[256];
    int lineno = 0;
    int rc = 0;
    struct quic_cfg pending;
    int have_pending = 0;

    while (fgets(line, sizeof(line), fp)) {
        lineno++;
        size_t l = strlen(line);
        if (l == 0) continue;
        if (line[l - 1] != '\n' && !feof(fp)) {
            fprintf(stderr, "udpdist: %s:%d: line too long (max %d); refusing to "
                            "guess where the directive ends\n",
                    path, lineno, UD_LINE_MAX - 1);
            rc = -1;
            break;
        }
        line[strcspn(line, "\r\n")] = '\0';
        char *t = trim(line);
        if (*t == '\0' || *t == '#' || *t == ';') continue;

        char *tok[MAX_TOK] = {0};
        int ntok = 0;
        char *save = t;
        for (char *p = strtok_r(save, " \t", &save); p && ntok < MAX_TOK;
             p = strtok_r(NULL, " \t", &save))
            tok[ntok++] = p;
        if (ntok == 0) continue;
        if (strtok_r(NULL, " \t", &save) != NULL) {
            fprintf(stderr, "udpdist: %s:%d: too many tokens (max %d)\n",
                    path, lineno, MAX_TOK);
            rc = -1;
            break;
        }

        char *eq = strchr(tok[0], '=');
        if (!eq) {
            fprintf(stderr, "udpdist: %s:%d: expected key=value, got '%s'\n",
                    path, lineno, tok[0]);
            rc = -1;
            break;
        }
        *eq = '\0';
        const char *k = tok[0];
        const char *v = eq + 1;

        err[0] = '\0';
        if (strcmp(k, "frontend") == 0) {
            rc = parse_frontend(svc, v, tok, err, sizeof(err));
        } else if (strcmp(k, "backend") == 0) {
            rc = parse_backend(svc, v, tok, err, sizeof(err));
        } else if (strcmp(k, "quic_config") == 0) {
            memset(&pending, 0, sizeof(pending));
            have_pending = 1;
            pending.config_id = atoi(v);
            pending.server_id_len = 1;
            pending.cid_len = 0;
            for (int i = 1; i < ntok; i++) {
                const char *a = NULL;
                if (attr_is(tok[i], "cid_len", &a)) pending.cid_len = atoi(a);
                else if (attr_is(tok[i], "server_id_len", &a)) pending.server_id_len = atoi(a);
                else if (attr_is(tok[i], "self_describing", &a)) pending.self_describing = atoi(a);
                else {
                    snprintf(err, sizeof(err), "unknown quic_config attribute '%s'", tok[i]);
                    rc = -1;
                    break;
                }
            }
            if (rc == 0) {
                rc = quic_configure(svc, &pending);
                if (rc != 0) snprintf(err, sizeof(err), "invalid quic_config %d", pending.config_id);
                have_pending = 0;
            }
        } else if (strcmp(k, "max_datagram") == 0) {
            long n = atol(v);
            if (n < 64 || n > 65535) {
                fprintf(stderr, "udpdist: %s:%d: max_datagram out of range (64..65535)\n",
                        path, lineno);
                rc = -1;
            } else {
                svc->max_datagram = (uint64_t)n;
            }
        } else if (strcmp(k, "skip_csum_offload_check") == 0) {
            svc->skip_csum_check = atoi(v) ? 1 : 0;
        } else if (strcmp(k, "allow_unverified_health") == 0) {
            svc->skip_health_check = atoi(v) ? 1 : 0;
        } else if (strcmp(k, "require_mac") == 0) {
            svc->require_mac = atoi(v) ? 1 : 0;
        } else {
            fprintf(stderr, "udpdist: %s:%d: unknown key '%s'\n", path, lineno, k);
            rc = -1;
        }
        if (rc != 0) {
            if (err[0]) fprintf(stderr, "udpdist: %s:%d: %s\n", path, lineno, err);
            break;
        }
    }
    (void)have_pending;
    fclose(fp);
    if (rc != 0) return -1;

    if (svc->nifaces > 0) {
        for (int i = 0; i < svc->nfronts; i++)
            if (svc->fronts[i].iface < 0) svc->fronts[i].iface = 0;
    }
    if (svc->nfronts == 0) {
        fprintf(stderr, "udpdist: %s: no frontends\n", path);
        return -1;
    }
    if (svc->nbacks == 0) {
        fprintf(stderr, "udpdist: %s: no backends\n", path);
        return -1;
    }
    if (svc->require_mac) {
        for (int i = 0; i < svc->nbacks; i++) {
            /* require_mac means "no backend may forward without a hardware
             * address in hand", not "the address must appear in the file".
             * A backend marked mac=auto is held to the same rule: it resolves
             * one before the service starts, or the service does not start. */
            if (!svc->backs[i].mac_configured && !svc->backs[i].mac_learned) {
                fprintf(stderr, "udpdist: %s: backend %s has no mac but "
                                "require_mac=1\n", path, svc->backs[i].id);
                return -1;
            }
        }
    }
    for (int i = 0; i < svc->nfronts; i++) {
        struct frontend *f = &svc->fronts[i];
        if (f->quic_mode == QUIC_MODE_QUIC_LB && svc->nquic == 0) {
            fprintf(stderr, "udpdist: %s: frontend %s requests quic_lb but no "
                            "quic_config is present; refusing to run because the "
                            "migration-safe claim would be untrue\n",
                    path, f->id);
            return -1;
        }
    }
    if (svc->nquic > 0) {
        for (int i = 0; i < svc->nbacks; i++) {
            if (!svc->backs[i].quic_sid_set) {
                fprintf(stderr, "udpdist: %s: backend %s has no sid but QUIC-LB "
                                "routing is configured\n", path, svc->backs[i].id);
                return -1;
            }
        }
        for (int i = 0; i < svc->nbacks; i++)
            for (int j = i + 1; j < svc->nbacks; j++)
                if (svc->backs[i].quic_sid_set && svc->backs[j].quic_sid_set &&
                    svc->backs[i].quic_sid == svc->backs[j].quic_sid) {
                    fprintf(stderr, "udpdist: %s: backends %s and %s share sid %llu\n",
                            path, svc->backs[i].id, svc->backs[j].id,
                            (unsigned long long)svc->backs[i].quic_sid);
                    return -1;
                }
    }
    return 0;
}
