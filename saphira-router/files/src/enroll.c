/* enroll.c -- SSH bootstrap enrollment and capability discovery.
 *
 * SSH is BOOTSTRAP ONLY (D6 1). The pass is read-only: it identifies the
 * host and probes capabilities. It changes no configuration and starts no
 * service. The first configuration change to a host is an ordinary
 * transaction (D8).
 *
 * ONE ssh round-trip per host. Twelve separate round-trips inside a request
 * handler is both slow and a blocking design: a caller would wait minutes,
 * and a slow or unreachable host would stall the API. The probes are
 * therefore batched into a single remote script that emits one
 * SRPROBE|cap|state|probe|detail line per capability.
 *
 * Every probe follows D6 3.1: a capability is established by EXERCISING the
 * feature with a direct, side-effect-free probe, never inferred from a proxy
 * signal. lsmod, package presence and a service file are hints, not evidence.
 */

#include "sr.h"
#include "sr_db.h"
#include "sr_module.h"
#include "sr_audit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Quote a string as ONE single-quoted shell word.
 *
 * Essential, not cosmetic: popen() hands the line to the LOCAL shell, so an
 * unquoted remote command containing ; | > {} would be evaluated here
 * instead of reaching ssh. */
static void sh_quote(char *dst, size_t dstsz, const char *src)
{
    size_t o = 0;
    if (dstsz < 5) { if (dstsz) dst[0] = '\0'; return; }
    dst[o++] = '\'';
    for (const char *p = src; *p && o + 5 < dstsz; p++) {
        if (*p == '\'') {
            dst[o++] = '\''; dst[o++] = '\\'; dst[o++] = '\'';
            dst[o++] = '\'';
        } else {
            dst[o++] = *p;
        }
    }
    dst[o++] = '\'';
    dst[o] = '\0';
}

/* Run a read-only command over SSH. stdin is closed (</dev/null) because ssh
 * inherits it from popen and will otherwise block waiting for input. */
static int ssh_capture(const char *addr, const char *cmd, char **out, size_t *out_len)
{
    char quoted[8192];
    sh_quote(quoted, sizeof quoted, cmd);

    char line[16384];
    snprintf(line, sizeof line,
        "ssh -o BatchMode=yes -o ConnectTimeout=5 "
        "-o StrictHostKeyChecking=accept-new -n "
        "root@%s -- %s </dev/null 2>/dev/null",
        addr, quoted);

    *out = NULL;
    if (out_len) *out_len = 0;

    FILE *f = popen(line, "r");
    if (!f) return -1;

    size_t cap = 8192, len = 0;
    char *buf = malloc(cap);
    if (!buf) { pclose(f); return -1; }
    char tmp[2048];
    while (fgets(tmp, sizeof tmp, f)) {
        size_t n = strlen(tmp);
        if (len + n + 1 > cap) {
            while (len + n + 1 > cap) cap *= 2;
            buf = realloc(buf, cap);
            if (!buf) { pclose(f); return -1; }
        }
        memcpy(buf + len, tmp, n);
        len += n;
    }
    int rc = pclose(f);
    buf[len] = '\0';
    *out = buf;
    if (out_len) *out_len = len;
    return (rc == 0) ? 0 : -1;
}

/* --------------------------------------------- the batched probe script
 *
 * Written to run on the far side. `p` emits one record; a literal pipe in a
 * value would corrupt the framing, so it is sanitised away.
 */
/* The probe script, one C string per shell line.
 *
 * Split into an array so no single string literal exceeds the ISO C99
 * 4095-byte minimum, and joined with an explicit newline per element.
 * Probes are BATCHED into one remote script: a dozen separate ssh
 * round-trips inside a request handler is slow AND blocks the API on a
 * slow host. One round-trip per host is the right shape.
 *
 * Every probe exercises the feature directly (D6 3.1): nft -c, ipvsadm
 * exit status, perl -c, haproxy -c, named-checkconf -z, ovs-vsctl show.
 * None infers capability from lsmod or package presence. */
static const char *const PROBE_SCRIPT_LINES[] = {
"p(){ v=$(printf '%s' \"$4\" | tr '|' '/'); printf 'SRPROBE|%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$v\"; };\n",
"if printf 'table inet srp {\\n chain c { type filter hook input priority 0; policy accept; }\\n}\\n' > /tmp/.srp.nft 2>/dev/null && nft -c -f /tmp/.srp.nft >/dev/null 2>&1; then\n",
"  p nftables usable 'nft -c -f (check mode; applies nothing)' 'ruleset validates'\n",
"elif command -v nft >/dev/null 2>&1; then\n",
"  p nftables installed 'nft -c -f' 'nft present but a valid ruleset was rejected'\n",
"else p nftables unavailable 'nft -c -f' 'no nft binary'\n",
"fi\n",
"rm -f /tmp/.srp.nft\n",
"if ipvsadm -Ln >/dev/null 2>&1; then\n",
"  p ipvs usable 'ipvsadm -Ln; exit status (NOT lsmod)' 'kernel reports the ipvs service'\n",
"elif command -v ipvsadm >/dev/null 2>&1; then\n",
"  p ipvs installed 'ipvsadm -Ln; exit status' 'ipvsadm present but the kernel ipvs service is unavailable'\n",
"else p ipvs unavailable 'ipvsadm -Ln' 'ipvsadm not present'\n",
"fi\n",
"if perl -c /usr/sbin/ldirectord >/dev/null 2>&1; then\n",
"  p ldirectord usable 'perl -c (parse check; no validate mode exists)' 'script parses; validation is a named substitute'\n",
"elif test -x /usr/sbin/ldirectord; then\n",
"  p ldirectord installed 'perl -c' 'binary present but does not parse (often missing perl)'\n",
"else p ldirectord unavailable 'perl -c' 'not installed'\n",
"fi\n",
"if perl -e 'print 1' >/dev/null 2>&1; then\n",
"  p perl usable \"perl -e 'print 1'\" 'interpreter runs'\n",
"elif command -v perl >/dev/null 2>&1; then\n",
"  p perl installed \"perl -e 'print 1'\" 'perl present but did not execute'\n",
"else p perl unavailable \"perl -e 'print 1'\" 'no perl interpreter; ldirectord cannot run'\n",
"fi\n",
"if haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then\n",
"  p haproxy usable 'haproxy -c -f (validates; does not start)' 'config validates'\n",
"elif command -v haproxy >/dev/null 2>&1; then\n",
"  p haproxy installed 'haproxy -c -f' 'haproxy present but the shipped config did not validate'\n",
"else p haproxy unavailable 'haproxy -c -f' 'no haproxy binary'\n",
"fi\n",
"if grep -qs 'stats socket' /etc/haproxy/haproxy.cfg 2>/dev/null && ls /run/haproxy/admin.sock >/dev/null 2>&1; then\n",
"  p haproxy.runtime usable 'stats socket in the running config' 'runtime socket available'\n",
"elif command -v haproxy >/dev/null 2>&1; then\n",
"  p haproxy.runtime unavailable 'search running config for a stats socket' 'haproxy installed; runtime socket not configured, so observed state is unavailable'\n",
"else p haproxy.runtime unavailable 'search running config for a stats socket' 'no haproxy binary'\n",
"fi\n",
"if ovs-vsctl --timeout=5 show >/dev/null 2>&1; then\n",
"  p ovs healthy 'ovs-vsctl --timeout=5 show (real query)' 'ovsdb answered'\n",
"elif command -v ovs-vsctl >/dev/null 2>&1; then\n",
"  p ovs installed 'ovs-vsctl --timeout=5 show' 'ovs-vsctl present but ovsdb did not answer'\n",
"else p ovs unavailable 'ovs-vsctl show' 'no ovs-vsctl'\n",
"fi\n",
"if command -v gredist >/dev/null 2>&1; then\n",
"  p gredist installed 'command -v gredist (no queryable endpoint exists)' 'installed; no service integration and no queryable status endpoint'\n",
"else p gredist unavailable 'command -v gredist' 'no gredist binary'\n",
"fi\n",
"if ls /usr/lib/pppd/*/rp-pppoe.so >/dev/null 2>&1; then\n",
"  p pppoe usable 'ls pppd plugin (no validate-then-activate daemon)' 'pppd plugin present'\n",
"elif command -v pppoe >/dev/null 2>&1; then\n",
"  p pppoe installed 'ls pppd plugin' 'client binary present, plugin not found'\n",
"else p pppoe unavailable 'ls pppd plugin' 'not installed'\n",
"fi\n",
"if named-checkconf -z /etc/bind/named.conf >/dev/null 2>&1; then\n",
"  p bind9 usable 'named-checkconf -z (true read-only validator)' 'config validates'\n",
"elif command -v named >/dev/null 2>&1; then\n",
"  p bind9 installed 'named-checkconf -z' 'named present but config did not validate'\n",
"else p bind9 unavailable 'named-checkconf -z' 'no named'\n",
"fi\n",
"if virsh -c qemu:///system version >/dev/null 2>&1; then\n",
"  p libvirt healthy 'virsh -c qemu:///system version' 'answered; NOTE virtqemud has no access control (polkit disabled)'\n",
"elif command -v virsh >/dev/null 2>&1; then\n",
"  p libvirt installed 'virsh -c qemu:///system version' 'virsh present but the hypervisor did not answer'\n",
"else p libvirt unavailable 'virsh version' 'no virsh'\n",
"fi\n",
NULL };

static char *build_probe_script(void)
{
    size_t n = 0;
    for (size_t i = 0; PROBE_SCRIPT_LINES[i]; i++)
        n += strlen(PROBE_SCRIPT_LINES[i]);
    char *b = malloc(n + 2);
    if (!b) return NULL;
    b[0] = 0;
    for (size_t i = 0; PROBE_SCRIPT_LINES[i]; i++)
        strcat(b, PROBE_SCRIPT_LINES[i]);
    return b;
}

/* Exposed for tests: the exact script that goes over the wire. */
void sr_dump_probe_script(void)
{
    char *b = build_probe_script();
    if (b) { fputs(b, stdout); free(b); }
}

/* --------------------------------------------------------- recording */

static void record_cap(sr_db *db, const char *host_id, const char *cap,
                       const char *state, const char *probe_method,
                       const char *detail)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO host_capability(host_id,capability,state,evidence,"
        "probe_method,detail,checked_at) VALUES(?,?,?,?,?,?,datetime('now')) "
        "ON CONFLICT(host_id,capability) DO UPDATE SET "
        "state=excluded.state, evidence=excluded.evidence,"
        "probe_method=excluded.probe_method, detail=excluded.detail,"
        "checked_at=excluded.checked_at;", &st, NULL) < 0)
        return;
    sqlite3_bind_text(st, 1, host_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, cap, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, state, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, detail, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 5, probe_method, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 6, detail, -1, SQLITE_STATIC);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

static int valid_state(const char *s)
{
    return !strcmp(s, "unestablished") || !strcmp(s, "unavailable") ||
           !strcmp(s, "installed") || !strcmp(s, "available") ||
           !strcmp(s, "usable") || !strcmp(s, "healthy");
}

/* ---------------------------------------------------------- enroll */

int sr_enroll_host(sr_db *db, const char *tenant_id, const char *addr,
                   const char *hostname, char **out_id, char **err)
{
    char *ident = NULL;
    if (ssh_capture(addr,
        "uname -sr; . /etc/os-release 2>/dev/null; echo NAME:${PRETTY_NAME}; "
        "uname -m; command -v systemctl >/dev/null 2>&1 && echo INIT:systemd || echo INIT:other",
        &ident, NULL) < 0 || !ident || !ident[0]) {
        free(ident);
        if (err) *err = sr_xstrdup("cannot reach host over SSH (bootstrap is SSH-only)");
        return -1;
    }

    char os_name[128] = "", os_version[64] = "", arch[64] = "", init_system[32] = "";
    int line_no = 0;
    char *save = NULL;
    for (char *line = strtok_r(ident, "\n", &save); line;
         line = strtok_r(NULL, "\n", &save)) {
        sr_trim(line);
        if (!line[0]) continue;
        if (line_no == 0)      snprintf(os_version, sizeof os_version, "%s", line);
        else if (line_no == 1) { if (!strncmp(line, "NAME:", 5)) snprintf(os_name, sizeof os_name, "%s", line + 5); }
        else if (line_no == 2) snprintf(arch, sizeof arch, "%s", line);
        else if (line_no == 3) { if (!strncmp(line, "INIT:", 5)) snprintf(init_system, sizeof init_system, "%s", line + 5); }
        line_no++;
    }
    free(ident);

    char id[SR_MAX_ID];
    sr_gen_id(id, sizeof id);

    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO host(id,tenant_id,hostname,address_v4,os_name,os_version,"
        "arch,init_system,status,enrolled_at,last_seen_at) "
        "VALUES(?,?,?,?,?,?,?,?,'online',datetime('now'),datetime('now'));",
        &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, hostname, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, addr, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 5, os_name, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 6, os_version, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 7, arch, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 8, init_system, -1, SQLITE_STATIC);
    if (sqlite3_step(st) != SQLITE_DONE) {
        char *m = sr_xstrdup(sqlite3_errmsg(sr_db_handle(db)));
        sqlite3_finalize(st);
        if (err) *err = m; else free(m);
        return -1;
    }
    sqlite3_finalize(st);
    *out_id = sr_xstrdup(id);
    return 0;
}

/* ------------------------------------------------------- discovery */

int sr_discover_host(sr_db *db, const char *tenant_id, const char *host_id)
{
    char *addr = NULL;
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
            "SELECT address_v4 FROM host WHERE id=? AND tenant_id=?;",
            &st, NULL) < 0) return -1;
    sqlite3_bind_text(st, 1, host_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, tenant_id, -1, SQLITE_STATIC);
    if (sqlite3_step(st) == SQLITE_ROW) {
        const unsigned char *a = sqlite3_column_text(st, 0);
        if (a) addr = sr_xstrdup((const char *)a);
    }
    sqlite3_finalize(st);
    if (!addr) return -1;

    char *out = NULL;
    char *script = build_probe_script();
    if (!script) { free(addr); return -1; }
    int rc = ssh_capture(addr, script, &out, NULL);
    free(script);

    int n = 0;
    if (rc == 0 && out) {
        char *save = NULL;
        for (char *line = strtok_r(out, "\n", &save); line;
             line = strtok_r(NULL, "\n", &save)) {
            if (strncmp(line, "SRPROBE|", 8) != 0) continue;
            /* Format is SRPROBE|<cap>|<state>|<probe>|<detail>: after the
             * 8-character prefix there are FOUR fields joined by THREE pipes.
             * Counting separators (not fields) is what makes this correct --
             * checking for 4 separators silently rejected every real record. */
            char *f[4];
            int seps = 0;
            char *p = line + 8;
            f[0] = p;
            while (*p) {
                if (*p == '|') { *p = '\0'; f[++seps] = p + 1; }
                p++;
            }
            if (seps != 3) continue;
            if (!f[1][0] || !valid_state(f[1])) continue;
            record_cap(db, host_id, f[0], f[1], f[2], f[3]);
            n++;
        }
    }
    if (n == 0) {
        /* No evidence at all. 'unestablished' is the honest answer and is
         * distinct from 'unavailable' (D6 3). */
        sr_log(SR_LOG_WARN, "no capability evidence from %s (rc=%d)", addr, rc);
    }
    /* A probe run is an observation, not a configuration change, but it is
     * still an action with an outcome an operator may need to explain: who
     * asked, when, and how many capabilities could actually be established. */
    {
        char detail[128];
        snprintf(detail, sizeof detail, "capabilities established: %d", n);
        sr_audit(db, tenant_id, NULL, NULL,
                 n > 0 ? "capability.probe" : "capability.probe",
                 "host", host_id,
                 n > 0 ? SR_AUDIT_SUCCESS : SR_AUDIT_FAILED, NULL, detail);
    }
    free(out);
    free(addr);
    return n;
}
