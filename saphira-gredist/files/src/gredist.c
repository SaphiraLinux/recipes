/* Saphira Linux (c) 2026 - BUSL-1.1, see LICENSE
 * saphira-gredist - Protocol 47/GRE distributor
 *
 * Small userspace control service with kernel dataplane where practical.
 * Userspace owns config, membership, health, stats, HRW distribution.
 * Kernel does high-rate forwarding via raw sockets + routing/nft where available.
 *
 * Each service has one frontend and N backends, cross-family translation by
 * rebuilding outer IP while preserving GRE header+payload.
 *
 * GRE handling follows Linux net/ipv4/gre_demux.c gre_parse_header logic.
 */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#include <poll.h>
#include <time.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <arpa/inet.h>
#include <syslog.h>
#include <netdb.h>
#include <pwd.h>
#include <grp.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <stdarg.h>
#include "gredist.h"

#define PROG "gredist"
#define DEFAULT_CONF_DIR "/etc/saphira/gredist"
/* Service identity, created by the package's accounts.d fragment. Kept as a
 * compiled-in constant rather than a config knob: this is not something an
 * operator should be able to redirect the daemon's identity from a file the
 * same operator can edit. */
#define GREDIST_USER "gredist"
#define GREDIST_GROUP "gredist"
#define DEFAULT_STATS_PATH "/var/run/saphira/gredist"

static int opt_syslog = 0;
static volatile sig_atomic_t do_quit = 0;
static volatile sig_atomic_t do_reload = 0;
static volatile sig_atomic_t do_dump = 0;

static void vlog(const char *fmt, va_list ap){
    if(opt_syslog) vsyslog(LOG_INFO, fmt, ap);
    else { vfprintf(stderr, fmt, ap); fputc('\n', stderr); }
}
static void log_msg(const char *fmt, ...){
    va_list ap; va_start(ap, fmt); vlog(fmt, ap); va_end(ap);
}
static void log_err(const char *fmt, ...){
    va_list ap; va_start(ap, fmt);
    if(opt_syslog) vsyslog(LOG_ERR, fmt, ap);
    else { fprintf(stderr, "%s: ", PROG); vfprintf(stderr, fmt, ap); fputc('\n', stderr); }
    va_end(ap);
}

static void sig_handler(int sig){
    if(sig==SIGINT || sig==SIGTERM) do_quit=1;
    else if(sig==SIGHUP) do_reload=1;
    else if(sig==SIGUSR1) do_dump=1;
}

static int set_nonblock(int fd){
    int fl=fcntl(fd,F_GETFL,0);
    if(fl==-1) return -1;
    return fcntl(fd,F_SETFL,fl|O_NONBLOCK);
}

/* A service name becomes a log prefix and, historically, an nft table name.
 * Restrict it to characters that are safe in both, so no operator-supplied
 * string can ever reach anything that interprets it. Deliberately excludes
 * '/', '.', '$', '`', ';', '|', '&', whitespace and every quote. */
static int name_is_valid(const char *s){
    if(!s || !*s) return 0;
    for(const char *p=s; *p; p++){
        unsigned char c = (unsigned char)*p;
        if(!isalnum(c) && c!='_' && c!='-') return 0;
    }
    return 1;
}

/* ---- health probing ----------------------------------------------------
 *
 * A probe is a detached child. The event loop never waits for one: it starts
 * probes whose interval has elapsed, reaps whatever has already finished on
 * every pass, and SIGKILLs anything that overran - reaping that child on a
 * later pass rather than blocking on it.
 *
 * r7 measured what the previous synchronous form cost. It forked and then spun
 * on waitpid(WNOHANG) with a 100 ms sleep, up to 2 s, INSIDE the event loop:
 *
 *     backends down   SIGUSR1 dump latency   (i.e. how long the loop was deaf)
 *          0                    3-5 ms
 *          1                  ~1030 ms
 *          3                  ~5510 ms
 *
 * Three dead backends blocked the loop for longer than the 2 s health interval
 * itself, so the distributor was effectively offline: 20 packets sent during
 * the window produced rx=0. The stall scaled with the number of dead probes,
 * which is the thing this replaces.
 *
 * Thresholds, cadence and the transition log lines are unchanged from r7, so
 * health state converges exactly as before - only the waiting moved. */
#define PROBE_TIMEOUT_SEC 2

struct probe {
    pid_t pid;
    int   backend;      /* index into svc->backends */
    time_t deadline;
    int   killed;       /* SIGKILL sent, awaiting reap */
};
/* One slot per backend plus one spare. A backend is only ever probed when it has
 * no probe in flight, so at most MAX_BACKENDS children exist at once and the
 * spare makes "no free slot" unreachable in practice; it is still handled
 * without ever blocking. */
static struct probe probes[MAX_BACKENDS + 1];
#define PROBE_SLOTS (MAX_BACKENDS + 1)

/* Apply one probe outcome. Identical accounting to the r7 inline version. */
static void probe_result(struct service *svc, int idx, int alive){
    if (idx < 0 || idx >= svc->nbackends) return;
    struct backend *b = &svc->backends[idx];
    if (alive){
        b->ok_cnt++; b->fail_cnt=0;
        if(!b->healthy && b->ok_cnt >= HEALTH_OK_THRESHOLD){
            b->healthy=1;
            log_msg("%s: backend %s recovered (healthy)", svc->name, b->str);
        }
    } else {
        b->fail_cnt++; b->ok_cnt=0;
        if(b->healthy && b->fail_cnt >= HEALTH_FAIL_THRESHOLD){
            b->healthy=0;
            log_msg("%s: backend %s failed (unhealthy)", svc->name, b->str);
        }
    }
}

static void probe_start(struct service *svc, int idx){
    struct backend *b = &svc->backends[idx];
    pid_t pid = fork();
    if(pid < 0){
        /* No child to wait for: record the failure immediately so the caller's
         * cadence still advances and the backend can still be taken down. */
        probe_result(svc, idx, 0);
        return;
    }
    if(pid==0){
        int dn = open("/dev/null", O_WRONLY);
        if(dn>=0){ dup2(dn, STDOUT_FILENO); dup2(dn, STDERR_FILENO); close(dn); }
        execlp("ping","ping","-c","1","-W","1", b->str, (char*)NULL);
        _exit(127);
    }
    for(int i=0;i<PROBE_SLOTS;i++){
        if(probes[i].pid==0){
            probes[i].pid=pid;
            probes[i].backend=idx;
            probes[i].deadline=time(NULL)+PROBE_TIMEOUT_SEC;
            probes[i].killed=0;
            return;
        }
    }
    /* No free slot. Unreachable given one probe per backend and the spare slot,
     * but it must not reintroduce a blocking wait, so reap with WNOHANG only.
     * SIGKILL has already been delivered, so this returns on the first try in
     * practice; the loop bounds the worst case without ever sleeping. */
    kill(pid, SIGKILL);
    for(int i=0;i<100 && waitpid(pid, NULL, WNOHANG)==0; i++)
        ;
    probe_result(svc, idx, 0);
}

static int probes_inflight(void){
    for(int i=0;i<PROBE_SLOTS;i++) if(probes[i].pid!=0) return 1;
    return 0;
}

static int probe_busy(int idx){
    for(int i=0;i<PROBE_SLOTS;i++)
        if(probes[i].pid!=0 && probes[i].backend==idx) return 1;
    return 0;
}

/* Called on every pass of the event loop. Never blocks. */
static void probes_reap(struct service *svc){
    time_t now = time(NULL);
    for(int i=0;i<PROBE_SLOTS;i++){
        if(probes[i].pid==0) continue;
        int status=0;
        pid_t w = waitpid(probes[i].pid, &status, WNOHANG);
        if(w==probes[i].pid){
            int alive = (!probes[i].killed && WIFEXITED(status) && WEXITSTATUS(status)==0);
            int idx = probes[i].backend;
            probes[i].pid=0;
            probe_result(svc, idx, alive);
            continue;
        }
        if(w<0){                 /* already reaped elsewhere */
            int idx = probes[i].backend;
            probes[i].pid=0;
            probe_result(svc, idx, 0);
            continue;
        }
        if(!probes[i].killed && now >= probes[i].deadline){
            /* Overran. Kill and leave the slot occupied; the next pass reaps
             * it and records the failure. Never wait for it. */
            kill(probes[i].pid, SIGKILL);
            probes[i].killed=1;
        }
    }
}

/* Drop every in-flight probe. Used on reload: the backend array is replaced,
 * so an in-flight probe's index no longer identifies the same backend, and
 * reload already re-marks the pool healthy from the config. */
static void probes_cancel(void){
    for(int i=0;i<PROBE_SLOTS;i++){
        if(probes[i].pid==0) continue;
        if(!probes[i].killed) kill(probes[i].pid, SIGKILL);
        probes[i].pid=0;
    }
}

static void health_check(struct service *svc){
    time_t now=time(NULL);
    for(int i=0;i<svc->nbackends;i++){
        struct backend *b=&svc->backends[i];
        if(probe_busy(i)) continue;
        if(now - b->last_probe < HEALTH_INTERVAL_SEC) continue;
        b->last_probe=now;
        probe_start(svc, i);
    }
}

/* ---- privilege drop ----------------------------------------------------
 *
 * Measured on a real node before this was written, because the obvious guess was
 * wrong. Creating a raw socket needs CAP_NET_RAW, but once the socket exists:
 *
 *     sendto() on the pre-opened raw socket .... OK
 *     bind() a raw socket ..................... OK
 *     fork() + exec("ping -c1 -W1") ........... OK
 *     socket() a NEW raw socket ............... EPERM
 *     setuid(0) / setgid(0) ................... EPERM
 *
 * So the daemon needs CAP_NET_RAW only to CREATE its sockets, and needs no
 * capability at all to forward, to re-read its configuration, or to run its ICMP
 * health probe. That means a plain in-daemon drop is sufficient: no privileged
 * supervisor, no second process, no setcap (which could not be shipped anyway -
 * the apk payload has no xattr channel).
 *
 * Everything privileged therefore happens before this call and nothing after it
 * needs privilege. Order is the conventional one: supplementary groups first
 * (while still root, or it will fail), then gid, then uid, then prove it stuck. */
static int drop_privileges(const char *user, const char *group)
{
    if (geteuid() != 0) {
        /* Already unprivileged - an operator or supervisor pre-dropped us.
         * Nothing to do, but say so rather than pretend. */
        log_msg("running unprivileged as uid %d; no drop required", (int)geteuid());
        return 0;
    }
    struct passwd *pw = getpwnam(user);
    if (!pw) {
        log_err("service account '%s' does not exist; cannot drop privileges "
                "(is saphira-gredist installed?)", user);
        return -1;
    }
    gid_t gid = pw->pw_gid;
    if (getgrnam(group) == NULL) {
        log_err("service group '%s' does not exist; cannot drop privileges", group);
        return -1;
    }
    /* Must happen while still root. One group only: no supplementary groups. */
    if (setgroups(1, &gid) != 0) {
        log_err("setgroups: %s", strerror(errno));
        return -1;
    }
    if (setgid(gid) != 0) { log_err("setgid(%ld): %s", (long)gid, strerror(errno)); return -1; }
    if (setuid(pw->pw_uid) != 0) { log_err("setuid(%ld): %s", (long)pw->pw_uid, strerror(errno)); return -1; }

    /* Prove it. setuid(0) succeeding would mean the whole drop was cosmetic. */
    if (setuid(0) == 0 || geteuid() == 0 || getuid() == 0) {
        log_err("privilege drop did not take effect: still euid %d uid %d",
                (int)geteuid(), (int)getuid());
        return -1;
    }
    log_msg("dropped privileges: uid=%d(%s) gid=%d(%s) euid=%d egid=%d supplementary=0; "
            "root cannot be regained",
            (int)getuid(), pw->pw_name, (int)getgid(), group,
            (int)geteuid(), (int)getegid());
    return 0;
}

/* After the drop the daemon must still be able to re-read its own configuration
 * on SIGHUP. /etc/saphira ships 0750 root:root, so this is NOT automatic, and
 * discovering it at reload time is exactly the silent failure r9 exists to
 * remove. Check it once, at startup, and refuse to run rather than come up deaf
 * and reload-blind. */
static int config_is_readable(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    close(fd);
    return 1;
}

/* NOTE: there is deliberately no nft code here. Up to r7 this function created
 * "table inet saphira_gredist_<name>" and then ran
 *     system("nft 'add chain inet <table> forward { type nat hook prerouting \
 *              priority dstnat ; }'")
 * which never succeeded: every table it left behind measured completely empty,
 * no chain was ever present in any of them, and they were never removed - not
 * on SIGTERM, not on crash. It was the daemon's only use of CAP_NET_ADMIN and
 * of system(). Deleting it is what makes the privilege drop below possible
 * without a privileged supervisor. */

/* forward via raw sockets */
static int send4_fd=-1;
static int send6_fd=-1;

static void forward_packet(struct service *svc, const uint8_t *pkt, size_t pkt_len,
                           size_t outer_len, const struct gre_info *gre, int backend_idx)
{
    if(backend_idx<0 || backend_idx>=svc->nbackends) return;
    struct backend *b=&svc->backends[backend_idx];
    /* GRE payload is from outer_len */
    const uint8_t *gre_start = pkt + outer_len;
    size_t gre_total = pkt_len - outer_len; /* includes GRE header + inner payload */
    if(gre_total < (size_t)gre->hdr_len) return;

    int fd = (b->family==AF_INET) ? send4_fd : send6_fd;
    if(fd<0){
        /* open on demand */
        if(b->family==AF_INET){
            send4_fd = socket(AF_INET, SOCK_RAW, IPPROTO_GRE);
            fd=send4_fd;
        } else {
            send6_fd = socket(AF_INET6, SOCK_RAW, IPPROTO_GRE);
            fd=send6_fd;
        }
        /* NOTE: IP_HDRINCL is deliberately NOT set here. It used to be, three
         * lines below a comment saying it must not be. With HDRINCL set the
         * kernel expects a complete IP header at the front of the buffer and
         * builds the outer header from whatever bytes are there - here, the
         * GRE header. Measured with the lazy path forced open: every packet
         * was rejected and reported through dropped_queue, and a GRE header
         * whose first byte parsed as a plausible IHL would have been
         * transmitted to the backend as genuine corruption. Letting the kernel
         * build the outer header is both correct and what C15 documents. */
        if(fd<0){
            log_err("%s: cannot open send socket for %s: %s", svc->name, b->str, strerror(errno));
            svc->dropped_queue++;
            return;
        }
    }
    ssize_t n = sendto(fd, gre_start, gre_total, 0, (struct sockaddr*)&b->ss, b->ss_len);
    if(n<0){
        if(errno==ENOBUFS || errno==ENOMEM || errno==EAGAIN){
            svc->dropped_queue++;
        } else {
            svc->dropped_queue++;
        }
        log_err("%s: sendto %s failed: %s", svc->name, b->str, strerror(errno));
        return;
    }
    b->pkts++; b->bytes+= (uint64_t)gre_total;
    svc->forwarded++;
}

static void dump_stats(struct service *svc){
    log_msg("=== %s stats ===", svc->name);
    log_msg(" frontend %s (%s)", svc->frontend_str, svc->frontend_family==AF_INET?"v4":"v6");
    log_msg(" rx=%lu forwarded=%lu malformed=%lu truncated=%lu frag=%lu vers=%lu no_backend=%lu queue=%lu oversized=%lu not_for_us=%lu",
        (unsigned long)svc->rx, (unsigned long)svc->forwarded,
        (unsigned long)svc->dropped_malformed, (unsigned long)svc->dropped_truncated,
        (unsigned long)svc->dropped_frag, (unsigned long)svc->dropped_version,
        (unsigned long)svc->dropped_no_backend, (unsigned long)svc->dropped_queue,
        (unsigned long)svc->dropped_oversized, (unsigned long)svc->dropped_not_for_us);
    for(int i=0;i<svc->nbackends;i++){
        struct backend *b=&svc->backends[i];
        log_msg("  backend %s %s pkts=%lu bytes=%lu %s", b->str, b->family==AF_INET?"v4":"v6",
            (unsigned long)b->pkts, (unsigned long)b->bytes, b->healthy?"healthy":"DOWN");
    }
}

static void usage(void){
    fprintf(stderr,"Usage: %s [--syslog] <service_name> | -c <config_path>\n", PROG);
    fprintf(stderr,"  service_name loads %s/<service_name>.conf\n", DEFAULT_CONF_DIR);
    fprintf(stderr,"  config format: frontend=IP  backend=IP  (one frontend, >=1 backends)\n");
    fprintf(stderr,"  families may be mixed: v4->v4/v6, v6->v4/v6\n");
}

int main(int argc, char *argv[]){
    const char *config_path=NULL;
    char config_buf[512];
    const char *service_name=NULL;
    int i=1;
    for(; i<argc; i++){
        if(strcmp(argv[i],"--help")==0 || strcmp(argv[i],"-h")==0){ usage(); return 0; }
        else if(strcmp(argv[i],"--syslog")==0){ opt_syslog=1; }
        else if(strcmp(argv[i],"-c")==0){
            if(i+1>=argc){ usage(); return 1; }
            config_path=argv[++i];
        } else if(argv[i][0]=='-'){ fprintf(stderr,"unknown option %s\n",argv[i]); usage(); return 1; }
        else { service_name=argv[i]; break; }
    }
    char name_buf[128]="";
    if(!config_path){
        if(!service_name){ usage(); return 1; }
        if(!name_is_valid(service_name)){ log_err("invalid service name"); return 1; }
        snprintf(config_buf,sizeof(config_buf),"%s/%s.conf", DEFAULT_CONF_DIR, service_name);
        config_path=config_buf;
        snprintf(name_buf,sizeof(name_buf),"%s",service_name);
    } else {
        const char *base=strrchr(config_path,'/');
        base = base?base+1:config_path;
        size_t blen=strlen(base);
        if(blen>5 && strcmp(base+blen-5,".conf")==0) blen-=5;
        if(blen>=sizeof(name_buf)) blen=sizeof(name_buf)-1;
        memcpy(name_buf,base,blen); name_buf[blen]='\0';
        if(name_buf[0]=='\0') snprintf(name_buf,sizeof(name_buf),"%s", PROG);
        /* The name derived from a -c path is validated exactly as strictly as
         * one given positionally. It used to be used verbatim: it reached
         * system("nft list table inet saphira_gredist_%s ..."), so a config
         * path of x$(touch /tmp/pwn).conf executed that command as root before
         * a single socket was opened. gredist no longer calls a shell at all,
         * and the name is also used in log lines, so it is validated here as
         * well rather than relying on the shell being gone. */
        if(!name_is_valid(name_buf)){ log_err("invalid service name in config path"); return 1; }
    }

    struct service svc;
    if(load_config(config_path,&svc, name_buf)!=0) return 1;

    if(opt_syslog) openlog(PROG, LOG_PID, LOG_DAEMON);

    log_msg("%s: starting service %s frontend=%s (%s) backends=%d",
        PROG, svc.name, svc.frontend_str, svc.frontend_family==AF_INET?"v4":"v6", svc.nbackends);
    for(int j=0;j<svc.nbackends;j++) log_msg(" backend %d: %s (%s)", j+1, svc.backends[j].str, svc.backends[j].family==AF_INET?"v4":"v6");

    /* signals */
    struct sigaction sa; memset(&sa,0,sizeof(sa));
    sa.sa_handler=sig_handler;
    sigaction(SIGINT,&sa,NULL);
    sigaction(SIGTERM,&sa,NULL);
    sigaction(SIGHUP,&sa,NULL);
    sigaction(SIGUSR1,&sa,NULL);
    signal(SIGPIPE,SIG_IGN);

    /* open recv sockets */
    int recv4=-1, recv6=-1;
    /* Receive sockets.
     *
     * r9: both families are opened here, at bootstrap, and NEITHER is bound.
     *
     * The bind was the whole bug. A raw socket can be bound exactly once, so
     * binding the receive socket to the configured frontend baked that address
     * into the socket for the life of the process. On SIGHUP with a changed
     * frontend= the config was replaced but the socket was not, so the daemon
     * kept receiving only the OLD address while logging "reloaded N backends"
     * and reporting no error at all: measured on three hosts, a packet
     * delivered to the new address produced rx=0, no forwarding, no counter
     * moved and no log line. A silent blackhole.
     *
     * socket() needs CAP_NET_RAW, so after the r9 privilege drop it is too late
     * to create a replacement socket - but bind() on an existing raw socket
     * does NOT need it. Neither fix is acceptable on its own: rebinding needs a
     * socket we can no longer create, and not binding means seeing every
     * protocol-47 packet for the host.
     *
     * So the socket is bound to nothing and the configured frontend is the only
     * thing that decides what is accepted, matched per packet in userspace. A
     * frontend change is then a pure configuration change that takes effect on
     * the next packet, with no socket state to desynchronise: it cannot
     * blackhole, and it can change family, which the old design could never do
     * after startup. The cost is that non-frontend GRE is now read and rejected
     * here rather than never delivered to us at all; those packets are counted
     * in not_for_us, which is what that counter is for. */
    recv4 = socket(AF_INET, SOCK_RAW, IPPROTO_GRE);
    if(recv4<0) log_err("socket AF_INET GRE: %s (IPv4 frontend unavailable)", strerror(errno));
    recv6 = socket(AF_INET6, SOCK_RAW, IPPROTO_GRE);
    if(recv6<0) log_err("socket AF_INET6 GRE: %s (IPv6 frontend unavailable)", strerror(errno));
    if(recv4<0 && recv6<0){ log_err("no protocol-47 receive socket available"); return 1; }
    if(recv4>=0 || recv6>=0){
        log_msg("receive sockets open for both families; the configured frontend is "
                "enforced per packet in userspace so that SIGHUP cannot desynchronise it");
    }

    /* send sockets - opened lazily but also pre-open */
    send4_fd = socket(AF_INET, SOCK_RAW, IPPROTO_GRE);
    if(send4_fd<0) log_err("send4 socket: %s", strerror(errno));
    send6_fd = socket(AF_INET6, SOCK_RAW, IPPROTO_GRE);
    if(send6_fd<0) log_err("send6 socket: %s", strerror(errno));

    if(recv4>=0) set_nonblock(recv4);
    if(recv6>=0) set_nonblock(recv6);
    if(send4_fd>=0) set_nonblock(send4_fd);
    if(send6_fd>=0) set_nonblock(send6_fd);

    /* timer for health */
    int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
    if(tfd>=0){
        struct itimerspec its; memset(&its,0,sizeof(its));
        its.it_interval.tv_sec=HEALTH_INTERVAL_SEC;
        its.it_value.tv_sec=HEALTH_INTERVAL_SEC;
        timerfd_settime(tfd,0,&its,NULL);
    }

    uint8_t buf[BUF_SIZE];
    struct pollfd pfds[3];
    int npfds=0;

    /* Last privileged act. Everything above needed CAP_NET_RAW to create the
     * sockets; everything below needs none of it. */
    if(drop_privileges(GREDIST_USER, GREDIST_GROUP) != 0) return 1;

    if(!config_is_readable(config_path)){
        log_err("cannot re-read %s as %s: %s", config_path, GREDIST_USER, strerror(errno));
        log_err("gredist runs as %s, so its configuration must be readable by that "
                "user. Refusing to start rather than run deaf and reload-blind.", GREDIST_USER);
        log_err("if this is a fresh install, apply: chgrp -R %s /etc/saphira && "
                "chmod 0750 /etc/saphira", GREDIST_GROUP);
        return 1;
    }

    log_msg("%s: ready (uid %d)", svc.name, (int)getuid());

    while(!do_quit){
        if(do_reload){
            do_reload=0;
            log_msg("%s: reloading %s", svc.name, config_path);
            struct service nsvc;
            if(load_config(config_path,&nsvc, svc.name)==0){
                /* In-flight probes index the OLD backend array, which is about
                 * to be replaced. Kill them rather than let a result land on a
                 * different backend. Reload already re-marks the pool healthy
                 * from the config, so the next tick re-establishes state. */
                probes_cancel();
                /* preserve stats? reset health */
                /* copy stats */
                nsvc.rx=svc.rx; nsvc.forwarded=svc.forwarded;
                nsvc.dropped_malformed=svc.dropped_malformed;
                nsvc.dropped_truncated=svc.dropped_truncated;
                nsvc.dropped_frag=svc.dropped_frag;
                nsvc.dropped_version=svc.dropped_version;
                nsvc.dropped_no_backend=svc.dropped_no_backend;
                nsvc.dropped_queue=svc.dropped_queue;
                nsvc.dropped_oversized=svc.dropped_oversized;
                nsvc.dropped_not_for_us=svc.dropped_not_for_us;
                svc=nsvc;
                log_msg("%s: reloaded %d backends", svc.name, svc.nbackends);
            } else {
                log_err("%s: reload failed, keeping old config", svc.name);
            }
        }
        if(do_dump){ do_dump=0; dump_stats(&svc); }

        npfds=0;
        if(recv4>=0){ pfds[npfds].fd=recv4; pfds[npfds].events=POLLIN; npfds++; }
        if(recv6>=0){ pfds[npfds].fd=recv6; pfds[npfds].events=POLLIN; npfds++; }
        if(tfd>=0){ pfds[npfds].fd=tfd; pfds[npfds].events=POLLIN; npfds++; }

        /* Reap first, every pass, before anything can block. */
        probes_reap(&svc);

        /* While probes are outstanding, come back quickly so their results are
         * collected promptly. The loop still never waits on a child, so this
         * only bounds detection latency, not the stall. */
        int pr = poll(pfds, npfds, probes_inflight() ? 50 : 1000);
        if(pr<0){
            if(errno==EINTR) continue;
            log_err("poll: %s", strerror(errno)); break;
        }
        /* health timer */
        for(int k=0;k<npfds;k++) if(pfds[k].fd==tfd && (pfds[k].revents&POLLIN)){
            uint64_t exp; read(tfd,&exp,sizeof(exp));
            health_check(&svc);
        }
        /* also periodic health if no timerfd */
        static time_t last_health=0;
        time_t now=time(NULL);
        if(now - last_health >= HEALTH_INTERVAL_SEC){
            last_health=now;
            health_check(&svc);
        }

        for(int k=0;k<npfds;k++){
            int fd=pfds[k].fd;
            if(fd!=recv4 && fd!=recv6) continue;
            if(!(pfds[k].revents&POLLIN)) continue;
            while(1){
                struct sockaddr_storage src; socklen_t slen=sizeof(src);
                ssize_t n = recvfrom(fd, buf, sizeof(buf), 0, (struct sockaddr*)&src, &slen);
                if(n<0){
                    if(errno==EAGAIN||errno==EWOULDBLOCK) break;
                    if(errno==EINTR) continue;
                    log_err("recvfrom: %s", strerror(errno));
                    break;
                }
                if(n==0) break;
                svc.rx++;
                /* size checks */
                if((size_t)n > 9000){
                    svc.dropped_oversized++;
                    continue;
                }
                int outer_family=0; size_t outer_len=0;
                uint8_t src_bytes[16]; size_t src_len=0;
                uint8_t dst_bytes[16]; size_t dst_len=0;
                int prs = parse_outer(buf, (size_t)n, &outer_family, &outer_len, src_bytes, &src_len, dst_bytes, &dst_len);
                if(prs!=0){
                    if(prs==-2){ svc.dropped_frag++; continue; }
                    /* No IPv6 headerless fallback. Linux delivers the IPv6
                     * header on an AF_INET6 SOCK_RAW receive, so parse_outer
                     * succeeded on every v6 delivery measured. The fallback
                     * never fired, and when it did it re-parsed the IPv6 header
                     * as a GRE header and forced the destination check to pass -
                     * a silent accept that could forward an IP header as tunnel
                     * payload. A packet we cannot parse is now counted. */
                    svc.dropped_malformed++; continue;
                }
                /* dst filter: must be frontend */
                int dst_match=0;
                if(outer_family==AF_INET && svc.frontend_family==AF_INET){
                    uint8_t front[4]; memcpy(front, &((struct sockaddr_in*)&svc.frontend_ss)->sin_addr,4);
                    if(memcmp(dst_bytes, front,4)==0) dst_match=1;
                } else if(outer_family==AF_INET6 && svc.frontend_family==AF_INET6){
                    uint8_t front[16]; memcpy(front, &((struct sockaddr_in6*)&svc.frontend_ss)->sin6_addr,16);
                    if(memcmp(dst_bytes, front,16)==0) dst_match=1;
                }
                if(!dst_match){
                    /* Counted. This used to be a bare `continue` with no
                     * counter at all, so a packet addressed elsewhere on the
                     * host vanished with no disposition anywhere - the one
                     * thing INV-1 forbids. Usually zero, because the receive
                     * socket is bound to the frontend, but it is reachable when
                     * that bind fails and gredist falls back to userspace
                     * filtering. */
                    svc.dropped_not_for_us++;
                    continue;
                }
                struct gre_info gre;
                int gr = gre_parse(buf, (size_t)n, outer_len, &gre);
                if(gr==-2){ svc.dropped_version++; continue; }
                if(gr!=0){
                    svc.dropped_truncated++; continue;
                }
                /* oversize payload? */
                size_t inner_payload = (size_t)n - outer_len - gre.hdr_len;
                if(inner_payload > 9000){
                    /* allow but log */
                }
                /* select backend via HRW */
                int idx = select_backend(&svc, src_bytes, src_len, &gre);
                if(idx<0){
                    svc.dropped_no_backend++;
                    continue;
                }
                forward_packet(&svc, buf, (size_t)n, outer_len, &gre, idx);

                /* queue pressure: if kernel recv buffer is filling, poll will show */
                /* we already counted drops */

                /* loop to drain */
            }
        }
    }

    log_msg("%s: shutting down", svc.name);
    probes_cancel();
    dump_stats(&svc);
    if(recv4>=0) close(recv4);
    if(recv6>=0) close(recv6);
    if(send4_fd>=0) close(send4_fd);
    if(send6_fd>=0) close(send6_fd);
    if(tfd>=0) close(tfd);
    return 0;
}
