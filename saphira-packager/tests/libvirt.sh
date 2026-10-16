#!/bin/sh

# libvirt umbrella + /var/run contract: static assertions over the
# libvirt recipe and its shipped service definitions (no build, no
# systemd required). Each case names the incident it locks in.
#
# Incident: libvirt r6/r7 shipped modular daemons with RUNSTATEDIR=/run
# while virt-ssh-helper hardcodes $LOCALSTATEDIR/run (/var/run), so
# every qemu+ssh connection died with ENOENT on
# /var/run/libvirt/libvirt-sock once /var/run became a real directory.
# r7 moved the stack to -Drunstatedir=/var/run. r8 restores the stable
# operator contract (enable/start/restart/stop/status libvirtd) as an
# umbrella over the ten modular daemons, without resurrecting the
# monolithic libvirtd binary.
#
# Live semantics (start brings all members active, sockets appear,
# restart/stop propagate, virsh connects) cannot run hermetically and
# are NOT asserted here; they are operator deploy checks on the target
# host after apk upgrade. This suite proves everything statically
# provable: unit graph, paths, and the no-monolith / no-auto-enable
# invariants.
#
# usage: libvirt.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
libvirt=$source_root/libvirt
files=$libvirt/files

fail()
{
	printf '%s\n' "libvirt: $*" >&2
	exit 1
}

# Ten modular members of the stack.
members="virtlogd virtlockd virtqemud virtstoraged virtnetworkd virtnodedevd virtsecretd virtproxyd virtinterfaced virtnwfilterd"

# The recipe must pin the runstatedir that the ssh-helper path expects.
grep -Fq -- '-Drunstatedir=/var/run' "$libvirt/recipe.sh" ||
	fail 'recipe lost -Drunstatedir=/var/run (ssh-helper ENOENT regresses)'

# The monolith must stay dead: it is disabled at configure time and no
# libvirtd binary or unit ExecStart may reference one.
grep -Fq -- '-Dlibvirtd=disabled' "$libvirt/recipe.sh" ||
	fail 'recipe lost -Dlibvirtd=disabled (monolith regresses)'
[ ! -e "$files/libvirtd" ] ||
	fail 'files/ must not contain a libvirtd binary'
grep -rn --include='*.service' -F '/usr/sbin/libvirtd' "$files" &&
	fail 'a unit ExecStarts the monolithic libvirtd binary'

# No package-time auto-enable: installation only lays files down. The
# operator explicitly chooses systemctl enable --now libvirtd
# (documentation comments are exempt; only recipe code is scanned).
grep -v '^[[:space:]]*#' "$libvirt/recipe.sh" | grep -n 'systemctl enable\|systemctl start\|rc-update\|rc-service' &&
	fail 'recipe must not enable or start services at install time'

# Umbrella unit exists and is an orchestrator, not a daemon.
[ -f "$files/libvirtd.service" ] ||
	fail 'libvirtd.service umbrella is missing'
grep -Fq 'Type=oneshot' "$files/libvirtd.service" ||
	fail 'libvirtd.service must be Type=oneshot (it owns no process)'
grep -Fq 'RemainAfterExit=yes' "$files/libvirtd.service" ||
	fail 'libvirtd.service must set RemainAfterExit=yes (stable status)'
grep -Fq 'ExecStart=/bin/true' "$files/libvirtd.service" ||
	fail 'libvirtd.service ExecStart must be /bin/true (packaged coreutils path)'
# Nothing in the tree ships /usr/bin/true (coreutils is --bindir=/bin
# since genesis; emacs-nox consumes /bin/true in hermetic build roots;
# nginx/openvswitch/breathgslb/freeradius units all use /bin/ paths in
# production). A host `which true` reporting /usr/bin/true is PATH
# order, not evidence -- systemd resolves ExecStart verbatim with no
# PATH lookup, and non-usrmerged has no /bin <-> /usr/bin alias.
grep -rn --include='*.service' -F '/usr/bin/true' "$files" &&
	fail 'libvirt units must not reference /usr/bin/true (nothing ships it)'
grep -v '^[[:space:]]*#' "$files/libvirtd.service" | grep -Fq 'systemctl' &&
	fail 'libvirtd.service must not shell out to systemctl'
grep -v '^[[:space:]]*#' "$files/libvirtd.service" | grep -Fq 'RuntimeDirectory=' &&
	fail 'libvirtd.service must not set RuntimeDirectory= (wrong tree: always /run)'
grep -Fq '[Install]' "$files/libvirtd.service" ||
	fail 'libvirtd.service needs [Install] or systemctl enable cannot succeed'

# Umbrella covers all ten members in both directions.
for m in $members; do
	grep -Fq "Wants=$m.service" "$files/libvirtd.service" 2>/dev/null ||
		grep -Eq "(^| )Wants=.*$m.service" "$files/libvirtd.service" ||
		fail "libvirtd.service Wants= is missing $m.service (start libvirtd would not start $m)"
	grep -Eq "(^| )After=.*$m.service" "$files/libvirtd.service" ||
		fail "libvirtd.service After= is missing $m.service (ordering vs $m undefined)"
done

# Install-time propagation: Wants= starts members at runtime but does
# NOT enable them. Also= must name exactly the complete modular stack
# so enable/disable of the umbrella enables/disables every member --
# the old operator contract (systemctl enable --now libvirtd installs
# the whole service for boot). No more, no fewer.
also_count=$(grep -c '^Also=' "$files/libvirtd.service" || true)
[ "$also_count" -eq 10 ] ||
	fail "libvirtd.service has $also_count Also= lines, want exactly 10 (one per member)"
for m in $members; do
	grep -Fq "Also=$m.service" "$files/libvirtd.service" ||
		fail "libvirtd.service Also= is missing $m.service (enable libvirtd would not enable $m)"
done

# Symmetry: every member ships both init formats, carries umbrella
# membership, keeps sockets under /var/run, and never touches /run.
for m in $members; do
	[ -f "$files/$m.service" ] ||
		fail "$m.service is missing (systemd coverage gap)"
	[ -f "$files/$m.initd" ] ||
		fail "$m.initd is missing (OpenRC coverage gap)"
	grep -Fq 'PartOf=libvirtd.service' "$files/$m.service" ||
		fail "$m.service lost PartOf=libvirtd.service (stop/restart would not propagate)"
	grep -v '^[[:space:]]*#' "$files/$m.service" | grep -Fq 'RuntimeDirectory=' &&
		fail "$m.service sets RuntimeDirectory= (wrong tree: always /run)"
	grep -Fq 'ReadWritePaths=/var/run/libvirt' "$files/$m.service" ||
		fail "$m.service lost ReadWritePaths=/var/run/libvirt"
	grep -Fq 'ExecStartPre=+/bin/install -d -o root -g root -m 0755 /var/run/libvirt' "$files/$m.service" ||
		fail "$m.service lost the /var/run/libvirt ExecStartPre"
	grep -v '/var/run/libvirt' "$files/$m.service" | grep -Fq '/run/libvirt' &&
		fail "$m.service references bare /run/libvirt (alias assumption regresses)"
	grep -Fq 'checkpath -d -o root:root -m 0755 /var/run/libvirt' "$files/$m.initd" ||
		fail "$m.initd lost the /var/run/libvirt start_pre"
done

# The two state-holding daemons keep their no-restart invariant
# (anchored: their own NEVER comment must not trip the grep).
for m in virtlogd virtlockd; do
	grep -q '^Restart=' "$files/$m.service" &&
		fail "$m.service sets Restart= (state corruption risk on retry loop)"
done

# OpenRC umbrella exists, delegates through OpenRC itself, and runs no
# daemon of its own.
[ -f "$files/libvirtd.initd" ] ||
	fail 'libvirtd.initd umbrella is missing'
grep -Fq '/sbin/service' "$files/libvirtd.initd" ||
	fail 'libvirtd.initd must delegate to member services via /sbin/service'
grep -q '^command=' "$files/libvirtd.initd" &&
	fail 'libvirtd.initd must not set command= (it owns no process)'
for fn in 'start()' 'stop()' 'status()'; do
	grep -Fq "$fn" "$files/libvirtd.initd" ||
		fail "libvirtd.initd is missing $fn (incomplete operator contract)"
done

printf '%s\n' 'libvirt umbrella + /var/run contract: OK'
