#!/bin/sh

# openssh: login accounting paths and databases.
#
# Two independent accounting formats, tested independently:
#   wtmp   (/var/log/wtmp): utmpx login/logout records, read by `last`.
#   lastlog (/var/log/lastlog): per-user last-login records, read by
#     shadow's `lastlog` (which the shadow recipe must enable; a writer
#     with no reader is an accounting gap, not a policy).
# utmp (/var/run/utmp) is the third, volatile leg for `who`.
#
# Mechanism (corrected 2026-10-23 after r4 proved it): musl's HEADERS
# are the single source of truth. openssh defines.h prefers _PATH_*
# over any CONF_* override, so configure pins (env vars and even the
# --with-lastlog flag) are silently dead whenever libc defines the
# macros -- r4 carried all three pins, passed a config.h assert, and
# still wrote /dev/null/wtmp. musl 0003 carries the real paths in
# paths.h AND utmp.h; this recipe pins nothing and asserts the LINKED
# BINARY instead (the only evidence that cannot lie). Service-side DB
# creation below is unchanged: files must exist at runtime.
#
# usage: login-accounting.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
recipe=$source_root/openssh/recipe.sh
initd=$source_root/openssh/files/sshd.initd
unit=$source_root/openssh/files/sshd.service

failures=0
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }
ok() { printf 'ok       %s\n' "$*"; }

# No dead configure pins: _PATH_* wins over CONF_* in defines.h, so
# location pins in this recipe would be silently inert (proven by r4).
# The paths live in musl's headers; the recipe asserts the binary.
if grep -E -q 'conf_(wtmp|utmp|lastlog)_location|--with-lastlog=' "$recipe"; then
	bad 'recipe carries dead configure location pins (headers own the paths)'
else
	ok 'no dead configure location pins'
fi

# The linked session binary is the true contract: real databases in,
# /dev/null neutering out. (Exercised at build time; asserted here so
# the requirement cannot be dropped without this suite failing.)
for needle in 'sshd-session' '/var/log/wtmp' '/var/log/lastlog' '/dev/null/wtmp'; do
	grep -Fq "$needle" "$recipe" ||
		bad "recipe never mentions $needle in its binary assertion"
done
ok 'binary assertion covers real paths and rejects neutering'

# Never silently disable accounting instead of fixing the paths.
if grep -E -q -- '--disable-(wtmp|utmp|lastlog|wtmpx)' "$recipe"; then
	bad 'recipe disables login accounting (fix the paths, never disable)'
else
	ok 'login accounting stays enabled'
fi

# Both service definitions create both databases when absent only.
for def in "$initd" "$unit"; do
	for db in /var/log/wtmp /var/log/lastlog; do
		grep -Fq "$db" "$def" ||
			bad "$def does not ensure $db"
	done
done
if grep -Fq '/var/log/wtmp' "$initd" && grep -Fq '/var/log/lastlog' "$initd" \
	&& grep -Fq '/var/log/wtmp' "$unit" && grep -Fq '/var/log/lastlog' "$unit"; then
	ok 'both service definitions ensure both databases'
fi

if [ "$failures" -gt 0 ]; then
	printf 'login-accounting: %d failure(s)\n' "$failures" >&2
	exit 1
fi
ok 'login accounting contract holds (pins, proofs, databases)'
