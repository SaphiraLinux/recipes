#!/bin/sh
# Boot progression guard: sysinit -> basic.target -> firstboot wizard.
#
# The new-disk investigation (Minimer 2026-11-07) ended at a journal
# that stops one second into sysinit with no error and no failure
# anywhere - which is precisely why this test exists in this form:
# the last journal line never proves causation. What CAN be proven
# without booting is that nothing in the shipped units can wedge the
# progression, and that every link of the chain is present.
#
# fhs-converge (read whole: files/saphira-fhs-converge.service plus
# libexec/ensure-fhs) performs bounded filesystem operations only
# (stat/lstat/readlink/rm/mkdir/rmdir/chown/chmod, no waits, no
# locks, no sleeps, no network, no mounts); every failure path exits
# non-zero loudly instead of hanging. The unit itself carries no
# Requires (a failure marks the unit failed without halting boot),
# no After= on anything past local-fs (it cannot wait on a target
# that waits on sysinit), stays Before=sysinit.target, and keeps
# systemd's default start timeout (no TimeoutStartSec=infinity, so
# even a stuck run is killed instead of wedging the boot).
#
# firstboot stays reachable: pulled by multi-user.target, ordered by
# the default dependencies (no DefaultDependencies=no that would
# float it before platform setup), gated by the marker (not by
# anything that could deadlock it).
#
# Asserted against the recipe sources, rootless, with no build. Where
# systemd-analyze and the units exist on the host, the combined graph
# is verified too; elsewhere that part reports a skip, never a pass.

set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
fhs=$here/../files/saphira-fhs-converge.service
firstboot=$here/../files/saphira-firstboot.service

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

for f in "$fhs" "$firstboot"; do
	test -r "$f" || { printf 'missing unit: %s\n' "$f" >&2; exit 1; }
done

printf '%s\n' '# fhs-converge cannot wedge sysinit'

# No After= on anything ordered at or after sysinit: waiting on a
# target that waits (transitively) on sysinit would deadlock the
# phase this unit is supposed to finish inside.
if /usr/bin/grep -E '^After=.*(basic|multi-user|network|getty|firstboot)' "$fhs"; then
	bad 'fhs-converge waits on a post-sysinit target (deadlock shape)'
else
	ok 'fhs-converge waits only on pre-sysinit ordering'
fi
# No Requires anywhere: a failed run must mark the unit failed and
# let the boot continue, never stop the transaction.
if /usr/bin/grep -E '^(Requires|Requisite|OnFailure|FailureAction|JobTimeoutAction)=' "$fhs"; then
	bad 'fhs-converge can fail the boot transaction (Requires/FailureAction present)'
else
	ok 'fhs-converge carries no Requires and no failure action'
fi
# No explicit infinite timeout: the default start timeout bounds even
# a stuck run instead of wedging sysinit forever.
if /usr/bin/grep -Eq '^TimeoutStartSec=(infinity|0)$' "$fhs"; then
	bad 'fhs-converge disables the start timeout'
else
	ok 'fhs-converge keeps a bounded start timeout'
fi
# Stays inside sysinit: ordered before it, pulled by it.
if /usr/bin/grep -Eq '^Before=.*sysinit\.target' "$fhs" &&
   /usr/bin/grep -qx 'WantedBy=sysinit.target' "$fhs"; then
	ok 'fhs-converge runs inside sysinit (Before it, wanted by it)'
else
	bad 'fhs-converge left its sysinit placement'
fi

printf '%s\n' '# firstboot stays reachable through the normal boot'

# Default dependencies intact: they order the wizard after basic.target
# (after sysinit, paths, slices, platform services). Floating it with
# DefaultDependencies=no put the wizard on screen while boot messages
# were still pending - removed once, must not return.
if /usr/bin/grep -Eq '^DefaultDependencies=no' "$firstboot"; then
	bad 'firstboot floats outside default ordering again'
else
	ok 'firstboot keeps default dependencies (ordered after basic.target)'
fi
# Pulled by the default target and gated by the marker only.
if /usr/bin/grep -qx 'WantedBy=multi-user.target' "$firstboot" &&
   /usr/bin/grep -qx 'ConditionPathExists=/etc/saphira-firstboot-required' "$firstboot"; then
	ok 'firstboot is pulled by multi-user.target and gated by the marker alone'
else
	bad 'firstboot lost its multi-user pull or its marker gate'
fi

printf '%s\n' '# the combined graph verifies on systemd hosts'

if ! command -v systemd-analyze >/dev/null 2>&1; then
	ok 'systemd-analyze absent: live-graph verification skipped (static guards passed)'
elif [ ! -f /usr/lib/systemd/system/saphira-firstboot.service ] ||
     [ ! -f /usr/lib/systemd/system/saphira-fhs-converge.service ]; then
	ok 'units absent here: live-graph verification skipped (static guards passed)'
else
	out=$(systemd-analyze verify saphira-firstboot.service saphira-fhs-converge.service systemd-networkd.service 2>&1 || true)
	if printf '%s\n' "$out" | /usr/bin/grep -Ei 'ordering cycle|cyclic|unfixable|deadlock' >/dev/null; then
		printf 'FAIL     live graph still cyclic:\n%s\n' "$out" >&2
		failures=$((failures + 1))
	else
		ok 'live graph verifies with no ordering cycle'
	fi
fi

if test "$failures" -ne 0; then
	printf 'boot-progression: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'boot-progression: OK'
