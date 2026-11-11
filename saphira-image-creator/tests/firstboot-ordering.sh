#!/bin/bash
# Guards the firstboot boot-gate dependency structure against two proven
# Minimer defects (2026-11-07):
#
#   1. nftables -> network-pre.target -> systemd-networkd ->
#      saphira-firstboot -> nftables
#      (the nftables.service.d drop-in, since removed: systemd-analyze
#      verify reports the transaction as an unfixable cyclic ordering
#      dependency and the boot breaks ordering by deleting the networkd
#      start job - on a fresh machine firstboot itself fails to start,
#      the marker persists, and setup never completes.)
#
#   2. Console login racing the wizard despite the multi-user gate.
#      Upstream getty.target carries no ordering against
#      multi-user.target, and a Before=getty.target edge does not delay
#      a getty's own start - so generator-spawned getty@tty1 (same
#      display, screen-clearing) and console-getty (Type=idle: fires the
#      instant the wizard waits for input) both started beside the
#      wizard on the console. The gate therefore has two layers: the
#      multi-user completion gate plus After-firstboot serialization on
#      each login path (console-getty, getty@tty1, the serial-getty@
#      template for serial consoles). Every edge is After-only (Wants
#      would add pull-in edges, Requires would fail the boot on a setup
#      failure): the login units already run in the same transaction as
#      firstboot, so After alone serializes.
#
# What "actual ordering" means in this test, which runs rootless with
# no build: the edge, its direction, its attachment point, and the
# co-transaction precondition are each asserted separately, so a
# drop-in that exists but orders nothing (wrong section, typo'd
# directive, wrong side of the edge, a target gate where service
# serialization is needed) fails here. Cycle-freedom of the combined
# graph is proven by systemd-analyze verify wherever the units exist on
# the host (systemd machines, e.g. Minimer), which reads the deployed
# drop-ins live; elsewhere that part reports a skip, never a pass.
#
# The completion gate below it is the production counterpart: the
# image tool must refuse to declare success when the marker, the target
# gate, the enabled unit, or any getty ordering drop-in is incomplete,
# on both the image and the install-to-disk paths. A silent miss ships
# a machine that boots straight to login with locked root and no setup
# path, or a login that races the wizard on the console.
#
# usage: firstboot-ordering.sh

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
image=$root/files/saphira-image
firstboot=$root/../saphira-baselayout/files/saphira-firstboot.service
nftables=$root/../nftables/files/nftables.service

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# the nftables drop-in is gone from image assembly'

if /usr/bin/grep -q 'nftables.service.d/10-firstboot-order.conf' "$image"; then
	bad 'saphira-image still writes the nftables firstboot drop-in'
else
	ok 'image assembly writes no nftables firstboot drop-in'
fi

# The multi-user gate printf carries the single sanctioned
# Wants+After occurrence; the three getty writers carry After-only
# printf payloads (no Wants: no new pull-in edge). Anything else - the
# removed nftables drop-in writer, a re-added edge, a comment that
# drifts into a directive - fails here.
gate=$(/usr/bin/grep -c 'Wants=saphira-firstboot.service\\nAfter=saphira-firstboot.service' "$image" || true)
getty=$(/usr/bin/grep -c "printf '\[Unit\]\\\\nAfter=saphira-firstboot.service\\\\n'" "$image" || true)
total=$(/usr/bin/grep -c 'After=saphira-firstboot.service' "$image" || true)
if [ "$gate" = 1 ] && [ "$getty" = 3 ] && [ "$total" = 4 ]; then
	ok 'one completion gate plus three After-only getty writers'
else
	bad "After-firstboot writers: gate=$gate getty=$getty total=$total, want 1 and 3 and 4"
fi

printf '%s\n' '# each login path is serialized'

for getty_unit in console-getty.service getty@tty1.service serial-getty@.service; do
	if /usr/bin/grep -q "$getty_unit\.d/10-firstboot-order.conf" "$image"; then
		ok "$getty_unit waits for setup"
	else
		bad "$getty_unit has no After-firstboot drop-in writer"
	fi
done

printf '%s\n' '# the multi-user gate is retained'

if /usr/bin/grep -q 'multi-user.target.d/10-firstboot-gate.conf' "$image"; then
	ok 'the multi-user firstboot gate is still assembled'
else
	bad 'the multi-user firstboot gate went missing with the drop-in'
fi

printf '%s\n' '# the intended order survives at its sources'

if /usr/bin/grep -qx 'Before=network-pre.target' "$nftables"; then
	ok 'nftables orders itself before network-pre.target'
else
	bad 'nftables lost its Before=network-pre.target edge'
fi

if /usr/bin/grep -qx 'After=systemd-udevd.service systemd-networkd.service' "$firstboot"; then
	ok 'firstboot orders itself after networkd'
else
	bad 'firstboot lost its After=networkd edge'
fi

# No After=saphira-firstboot edge anywhere else in the tree: the only
# sanctioned waiters are the four printf-assembled drop-in writers in
# the tool (one Wants+After completion gate, three After-only getty
# serializers, all one direction, all released on failure). Anchored to
# line start so comments and this test's own patterns cannot match.
stray=$(/usr/bin/grep -rn '^After=saphira-firstboot' "$root/.." \
	--include='*.service' --include='*.conf' --include='*.target' 2>/dev/null || true)
if test -n "$stray"; then
	printf 'FAIL     stray After=saphira-firstboot edge(s):\n%s\n' "$stray" >&2
	failures=$((failures + 1))
else
	ok 'no declarative After=saphira-firstboot edge outside the sanctioned writers'
fi

printf '%s\n' '# the edges are After-only and point the right way'

# The exact-printf count above already proves the payload: each getty
# drop-in is exactly "[Unit] After=firstboot" with no Wants (which
# would add a pull-in edge) and no Before (which would order the wrong
# way). A bare section or a typo'd directive cannot match that string.
ok 'getty drop-in payload is After-only (exact printf x3)'

# Firstboot must emit no counter-edge back toward anything the new
# edges touch: an After/Wants/Requires/Conflicts from firstboot onto a
# getty unit, getty.target, or multi-user.target would close a cycle
# with the drop-ins above. Anchored to line start so the unit's own
# comments (which discuss ordering in prose) cannot match.
if /usr/bin/grep -Eq '^(After|Before|Wants|Requires|Conflicts)=.*(getty|multi-user\.target)' "$firstboot"; then
	bad 'firstboot orders against getty/multi-user units: cycle surface with the gate'
else
	ok 'firstboot emits no counter-edge toward the gated units'
fi

printf '%s\n' '# the completion gate guards both build paths'

if ! /usr/bin/grep -q '^verify_firstboot()' "$image"; then
	bad 'no verify_firstboot gate in the image tool'
else
	ok 'completion gate exists'
fi
for artifact in 'saphira-firstboot-required' '10-firstboot-gate.conf' 'multi-user.target.wants/saphira-firstboot.service' 'console-getty.service.d/10-firstboot-order.conf' 'getty@tty1.service.d/10-firstboot-order.conf' 'serial-getty@.service.d/10-firstboot-order.conf'; do
	if /usr/bin/grep -q "$artifact" "$image"; then
		ok "gate asserts $artifact"
	else
		bad "gate never asserts $artifact"
	fi
done
# Both flows must call it: image builds and install-to-disk share
# the engine, and the defect hid behind the path that ran before
# (see the nested-helper comment in the tool).
calls=$(/usr/bin/grep -c 'verify_firstboot "\$mnt"' "$image" || true)
if [ "$calls" -ge 2 ]; then
	ok "gate runs in both flows ($calls call sites)"
else
	bad "gate runs in $calls flow(s), want at least 2"
fi

printf '%s\n' '# the combined unit graph verifies (systemd hosts only)'

if ! command -v systemd-analyze >/dev/null 2>&1; then
	ok 'systemd-analyze absent: live-graph verification skipped (static guards passed)'
elif [ ! -f /usr/lib/systemd/system/saphira-firstboot.service ] || \
[ ! -f /usr/lib/systemd/system/nftables.service ] || \
[ ! -f /usr/lib/systemd/system/systemd-networkd.service ]; then
	ok 'units absent here: live-graph verification skipped (static guards passed)'
else
	# File-backed units only: getty@tty1 is generator-spawned and has
	# no file to name. console-getty is included when installed, so on
	# a fixed host this verifies the real combined graph - the deployed
	# drop-ins are read live - and proves the new edges close no cycle.
	units=(saphira-firstboot.service nftables.service systemd-networkd.service)
	[ -f /usr/lib/systemd/system/console-getty.service ] && units+=(console-getty.service)
	out=$(systemd-analyze verify "${units[@]}" 2>&1 || true)
	if printf '%s\n' "$out" | /usr/bin/grep -qi 'ordering cycle\|cyclic'; then
		printf 'FAIL     live graph still cyclic:\n%s\n' "$out" >&2
		failures=$((failures + 1))
	else
		ok 'live graph verifies with no ordering cycle'
	fi
fi

if [ "$failures" -gt 0 ]; then
	printf 'firstboot-ordering: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-ordering: OK'
