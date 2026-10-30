#!/bin/sh

# openssh: sshd OpenRC first-start host-key generation.
#
# Hermetic and rootless: a user+mount namespace over-mounts /etc/ssh
# with scratch and /run with a tmpfs, so the live host keys are never
# touched. Sourcing the real initd with the real OpenRC helper
# functions proves, in order:
#   1. no host keys initially;
#   2. OpenRC start_pre generates them (ssh-keygen -A);
#   3. sshd -t passes (it runs only after the keys exist: with the old
#      initd this same flow fails, which is the regression coverage);
#   4. a second start_pre leaves every key hash unchanged (idempotent,
#      existing keys never replaced) with normal ownership/modes.
#
# usage: sshd-hostkeys.sh [INITD [SSHD_CONFIG]]
#   INITD defaults to the recipe file beside this suite, so the test
#   exercises the reviewed source, not whatever is installed.
#   Pass an assembled root's /etc/init.d/sshd and /etc/ssh/sshd_config
#   to prove the published, as-assembled payload instead.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
initd=${1:-$here/../files/sshd.initd}
config=${2:-$here/../files/sshd_config}
functions=/lib/rc/sh/functions.sh

fail() {
	printf 'sshd-hostkeys: %s\n' "$*" >&2
	exit 1
}

[ -f "$initd" ] || fail "initd missing: $initd"
[ -f "$config" ] || fail "sshd_config missing: $config"
[ -f "$functions" ] || fail "OpenRC helpers missing: $functions"
command -v unshare >/dev/null 2>&1 || fail "unshare missing"
command -v /usr/sbin/sshd >/dev/null 2>&1 || fail "sshd missing"
command -v /usr/bin/ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen missing"

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/sshd-hostkeys.XXXXXX") ||
	fail 'cannot create a work directory'
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

mkdir -p "$work/ssh" "$work/run" "$work/empty" || fail 'cannot stage scratch mounts'
chmod 0755 "$work/empty" || fail 'cannot mode scratch privsep dir'
# The server config under test (shipped config by default, or the
# assembled root's copy for clean-root proofs). Its HostKey lines
# point at /etc/ssh, which the namespace over-mounts with scratch.
cp "$config" "$work/ssh/sshd_config" ||
	fail 'cannot stage sshd_config'

checks=0
ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

# 1. no host keys initially.
if ls "$work/ssh"/ssh_host_* >/dev/null 2>&1; then
	fail 'scratch already contains host keys'
fi
ok 'no host keys initially'

# One start_pre run inside the namespace. Real initd, real helpers,
# real binaries; /etc/ssh, /run and /var/empty are over-mounted.
# (/var/empty needs its own mount: host root-owned files appear as
# nobody inside the namespace, and sshd -t rightly refuses a
# privsep dir it cannot prove is root-owned.)
cat > "$work/runner.sh" <<EOF
#!/bin/sh
mount --bind "$work/ssh" /etc/ssh || exit 1
mount -t tmpfs tmpfs /run || exit 1
mount --bind "$work/empty" /var/empty || exit 1
. "$functions"
. "$initd"
start_pre
EOF
chmod 0755 "$work/runner.sh"

unshare -rm "$work/runner.sh" ||
	fail 'first start_pre failed (keys were not generated before sshd -t)'

# 2. keys were generated, with normal ownership/modes.
priv=$(ls "$work"/ssh/ssh_host_*_key 2>/dev/null | grep -v '\.pub$' || true)
[ -n "$priv" ] || fail 'no private host keys after first start'
for k in $priv; do
	[ "$(stat -c '%a' "$k")" = 600 ] || fail "private key mode wrong: $k"
	[ "$(stat -c '%a' "$k.pub")" = 644 ] || fail "public key mode wrong: $k.pub"
done
ok "first start generated $(echo "$priv" | wc -l) host key type(s) with 0600/0644 modes"

# 3. sshd -t passes (already proven inside start_pre, re-assert directly
# against the scratch config for a clean signal).
unshare -rm sh -c "mount --bind '$work/ssh' /etc/ssh && mount -t tmpfs tmpfs /run && mount --bind '$work/empty' /var/empty && /usr/sbin/sshd -t -f '$work/ssh/sshd_config'" ||
	fail 'sshd -t failed after key generation'
ok 'sshd -t passes'

# 4. second start leaves every key hash unchanged.
before=$(cd "$work/ssh" && sha256sum ssh_host_* | sort)
unshare -rm "$work/runner.sh" ||
	fail 'second start_pre failed'
after=$(cd "$work/ssh" && sha256sum ssh_host_* | sort)
[ "$before" = "$after" ] || fail 'second start changed host keys'
ok 'second start leaves key hashes unchanged'

# 5. a corrupt host key fails start_pre (SEV 2026-10-23: sshd -t must
# gate the start, never merely log while sshd starts degraded).
mkdir -p "$work/ssh-bad" || fail 'cannot create bad-key scratch'
cp -a "$work"/ssh/ssh_host_* "$work/ssh-bad/" || fail 'cannot copy keys'
printf 'corrupt\n' > "$work/ssh-bad/$(cd "$work/ssh-bad" && ls *_key.pub | head -1)" ||
	fail 'cannot corrupt scratch key'
cat > "$work/bad-runner.sh" <<EOF
#!/bin/sh
mount --bind "$work/ssh-bad" /etc/ssh || exit 1
mount -t tmpfs tmpfs /run || exit 1
mount --bind "$work/empty" /var/empty || exit 1
. "$functions"
. "$initd"
start_pre
EOF
chmod 0755 "$work/bad-runner.sh"
if unshare -rm "$work/bad-runner.sh" >/dev/null 2>&1; then
	fail 'start_pre succeeded with a corrupt host key (sshd -t must gate the start)'
fi
ok 'corrupt host key fails start_pre'

printf 'sshd-hostkeys: OK (%s checks)\n' "$checks"
