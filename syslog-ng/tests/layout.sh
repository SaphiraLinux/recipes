#!/bin/sh
# syslog-ng layout regression test: r2 keeps the config under /etc/syslog-ng
# and keeps runtime/state out of forbidden usr/var and usr/etc.
set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
recipe="$dir/recipe.sh"
initd="$dir/files/syslog-ng.initd"
service="$dir/files/syslog-ng.service"
tmpfiles="$dir/files/syslog-ng.tmpfiles"
config="$dir/files/syslog-ng.conf"
fail=0

check() {
	name=$1
	shift
	if "$@" >/dev/null 2>&1; then
		printf 'ok: %s\n' "$name"
	else
		printf 'FAIL: %s\n' "$name"
		fail=1
	fi
}

check "recipe exists" test -f "$recipe"
check "openrc unit exists" test -f "$initd"
check "systemd unit exists" test -f "$service"
check "tmpfiles fragment exists" test -f "$tmpfiles"
check "packaged config exists" test -f "$config"
check "package-specific config root" grep -F -q -- '--sysconfdir=/etc/syslog-ng' "$recipe"
check "explicit local state root" grep -F -q -- '--localstatedir=/var' "$recipe"
check "openrc config path" grep -F -q -- '--cfgfile=/etc/syslog-ng/syslog-ng.conf' "$initd"
check "openrc persist path" grep -F -q -- '--persist-file=/var/lib/syslog-ng/syslog-ng.persist' "$initd"
check "openrc control path" grep -F -q -- '--control=/var/run/syslog-ng/syslog-ng.ctl' "$initd"
check "openrc pid path" grep -F -q -- '--pidfile=/var/run/syslog-ng/syslog-ng.pid' "$initd"
check "systemd config path" grep -F -q -- '--cfgfile=/etc/syslog-ng/syslog-ng.conf' "$service"
check "systemd persist path" grep -F -q -- '--persist-file=/var/lib/syslog-ng/syslog-ng.persist' "$service"
check "systemd control path" grep -F -q -- '--control=/var/run/syslog-ng/syslog-ng.ctl' "$service"
check "systemd pid path" grep -F -q -- '--pidfile=/var/run/syslog-ng/syslog-ng.pid' "$service"
check "systemd runtime/state prep" grep -F -q -- 'ExecStartPre=/bin/mkdir -p /var/run/syslog-ng /var/lib/syslog-ng' "$service"
check "tmpfiles runtime dir" grep -F -q -- 'd /var/run/syslog-ng 0755 root root -' "$tmpfiles"
check "tmpfiles state dir" grep -F -q -- 'd /var/lib/syslog-ng 0755 root root -' "$tmpfiles"
check "packaged config target" grep -F -q -- '"$PKGDEST/etc/syslog-ng/syslog-ng.conf"' "$recipe"
check "tmpfiles install target" grep -F -q -- '"$PKGDEST/usr/lib/tmpfiles.d/syslog-ng.conf"' "$recipe"
check "state dir install target" grep -F -q -- '"$PKGDEST/var/lib/syslog-ng"' "$recipe"
check "forbidden payload guard" grep -F -q -- 'unexpected usr/var or usr/etc in payload' "$recipe"

if grep -E -q -- 'install .*(usr/var|usr/etc)' "$recipe"; then
	printf 'FAIL: recipe installs into usr/var or usr/etc\n'
	fail=1
else
	printf 'ok: no usr/var or usr/etc install target\n'
fi

exit "$fail"
