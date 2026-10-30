#!/bin/bash
# Image-creator appliance: the usb-creator target, its profile, its
# menu, and the ZFS creation branch. The appliance's sole purpose is
# writing Saphira/SaphiraD destination systems to disks; it never alters
# existing profiles.
#
# Plan-level checks run through `plan` (static, no privileges). Shell
# functions are extracted verbatim and executed against fixtures, so
# the tests cannot drift from the shipped engine.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
tool=${SAPHIRA_IMAGE:-$root/../saphira-image-creator/files/saphira-image}
profiles=$root/files/profiles
menu=$root/files/saphira-image-creator-menu

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf '%s\n' '# appliance profile intentions resolve'

	while read -r pkg; do
		[ -n "$pkg" ] || continue
		base=$pkg
		case $base in
		*-dev) base=${base%-dev} ;;
		*-doc) base=${base%-doc} ;;
		esac
		if [ -f "$root/../$base/recipe.sh" ]; then
		ok "profile intention resolves: $pkg"
	else
		bad "profile intention missing: $pkg"
	fi
done <<EOF
$(awk '{ line = $0; sub(/#.*$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line) }
	line == "" { next } { print line }' "$profiles/image-creator-appliance")
EOF

printf '%s\n' '# installer profile intentions'

installer_pkgs=$(awk '{ line = $0; sub(/#.*$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line) }
	line == "" { next } { print line }' "$profiles/image-installer-appliance")
for want in saphira-base saphira-kernel-7.2.3 systemd grub e2fsprogs dosfstools dialog udev bash vim iproute2 findutils util-linux kmod saphira-image-creator saphira-install-tools saphira-zfs-7.2.3 saphira-zfs-userspace; do
	printf '%s\n' "$installer_pkgs" | grep -qxF "$want" &&
		ok "installer profile carries $want" || bad "installer profile lacks $want"
done
for banned in saphira-network dhcpcd saphira-image-firstboot; do
	printf '%s\n' "$installer_pkgs" | grep -qxF "$banned" &&
		bad "installer profile still carries $banned" || ok "installer profile excludes $banned"
done

printf '%s\n' '# internal usb-creator target row (not offered by the menu)'

"$tool" list-targets 2>/dev/null | grep -q '^usb-creator *bios *openrc *image-creator-appliance' &&
	ok "usb-creator bios openrc image-creator-appliance listed" ||
	bad "usb-creator target row missing or wrong"
"$tool" list-targets 2>/dev/null | grep -q '^usb-installer-appliance *hybrid *systemd *image-installer-appliance' &&
	ok "usb-installer-appliance hybrid systemd image-installer-appliance listed" ||
	bad "usb-installer-appliance target row missing or wrong"

printf '%s\n' '# internal usb-creator plan fits 512M'

"$tool" plan --target usb-creator --size 512M >"$work/plan.txt" 2>"$work/plan.err" ||
	bad "usb-creator 512M plan refused: $(cat "$work/plan.err")"
last_end=$(/usr/bin/grep '^start=' "$work/plan.txt" |
	/usr/bin/sed -n 's/^start=\([0-9]*\), size=\([0-9]*\).*/\1 \2/p' |
	/usr/bin/awk '{ end = $1 + $2; last = end } END { print last }')
total=$((512 * 1024 * 1024 / 512))
usable_last=$((total - 34))
[ -n "$last_end" ] && [ "$last_end" -le "$usable_last" ] &&
	ok "usb-creator 512M plan fits (ends $last_end, last usable $usable_last)" ||
	bad "usb-creator 512M plan overflows (ends ${last_end:-none})"

printf '%s\n' '# installer plan fits 640M'

"$tool" plan --target usb-installer-appliance --size 640M >"$work/installer-plan.txt" 2>"$work/installer-plan.err" ||
	bad "usb-installer-appliance 640M plan refused: $(cat "$work/installer-plan.err")"
installer_end=$(/usr/bin/grep '^start=' "$work/installer-plan.txt" |
	/usr/bin/sed -n 's/^start=\([0-9]*\), size=\([0-9]*\).*/\1 \2/p' |
	/usr/bin/awk '{ end = $1 + $2; last = end } END { print last }')
installer_total=$((640 * 1024 * 1024 / 512))
installer_usable=$((installer_total - 34))
[ -n "$installer_end" ] && [ "$installer_end" -le "$installer_usable" ] &&
	ok "usb-installer-appliance 640M plan fits (ends $installer_end, last usable $installer_usable)" ||
	bad "usb-installer-appliance 640M plan overflows (ends ${installer_end:-none})"

printf '%s\n' '# zfs plan carries boot plus pool'

"$tool" plan --target bios-saphira --size 8G --rootfs zfs >"$work/zfs.txt" 2>"$work/zfs.err" ||
	bad "zfs plan refused: $(cat "$work/zfs.err")"
/usr/bin/grep -q 'name="boot"' "$work/zfs.txt" &&
	/usr/bin/grep -q 'name="zfs"' "$work/zfs.txt" &&
	ok "zfs plan has boot and pool partitions" ||
	bad "zfs plan lacks boot/pool partitions"
/usr/bin/grep -q '6A898CC3-1DD2-11B2-99A6-080020736631' "$work/zfs.txt" &&
	ok "pool partition carries the Solaris root type" ||
	bad "pool partition type wrong"
bootsz=$(/usr/bin/grep 'name="boot"' "$work/zfs.txt" |
	/usr/bin/sed -n 's/^start=[0-9]*, size=\([0-9]*\).*/\1/p')
[ "$bootsz" = "$((256 * 2048))" ] &&
	ok "/boot defaults to 256MiB" ||
	bad "/boot size ${bootsz:-none}, want $((256 * 2048)) sectors"

printf '%s\n' '# zfs refusals fail closed'

"$tool" plan --target bios-saphira --size 8G --rootfs zfs --boot-size 64 > /dev/null 2>&1 &&
	bad "--boot-size 64 accepted" || ok "--boot-size 64 refused"
"$tool" plan --target usb-installer --size 8G --rootfs zfs > /dev/null 2>&1 &&
	bad "hybrid+zfs accepted" || ok "hybrid+zfs refused"
"$tool" plan --target bios-saphira --size 8G --rootfs xfs > /dev/null 2>&1 &&
	bad "--rootfs xfs accepted" || ok "--rootfs xfs refused"
"$tool" plan --target bios-saphira --size 8G --rootfs zfs --pool 'a/b' > /dev/null 2>&1 &&
	bad "bad pool name accepted" || ok "bad pool name refused"

printf '%s\n' '# dataset naming follows the init flavor'

sed -n '/^dataset_name_for()/,/^}/p' "$tool" > "$work/ds.sh"
INIT=openrc
# shellcheck disable=SC1090
. "$work/ds.sh"
[ "$(INIT=openrc dataset_name_for)" = saphira ] &&
	[ "$(INIT=systemd dataset_name_for)" = saphirad ] &&
	ok "datasets tank/ROOTS/saphira|saphirad" ||
	bad "dataset naming wrong"

printf '%s\n' '# zfs target requirement fails closed without kmod'

sed -n '/^require_zfs_target()/,/^}/p' "$tool" > "$work/req.sh"
die() { printf 'refused: %s\n' "$*" >&2; return 1; }
# shellcheck disable=SC1090
. "$work/req.sh"
printf 'saphira-base\nopenrc\n' > "$work/bare.profile"
INIT=openrc POOL=tank
if require_zfs_target "$work/bare.profile" 2>/dev/null; then
	bad "bare profile accepted for zfs root"
else
	ok "bare profile refused for zfs root"
fi
printf 'saphira-base\nsaphira-zfs-7.2.3\nsaphira-zfs-userspace\n' > "$work/zfs.profile"
if require_zfs_target "$work/zfs.profile" 2>/dev/null; then
	ok "kmod+userspace profile accepted for zfs root"
else
	bad "kmod+userspace profile refused for zfs root"
fi

printf '%s\n' '# menu and service exist and agree'

test -x "$menu" || test -r "$menu" || bad "creator menu missing"
command -v sh >/dev/null && sh -n "$menu" && ok "creator menu parses" || bad "creator menu syntax"
grep -q 'export TERM=${TERM:-linux}' "$menu" || bad "creator menu TERM default missing"
grep -q 'install-to-disk' "$menu" && ok "menu drives install-to-disk" || bad "menu never calls the engine"
grep -q '/dev/disk/by-id' "$menu" && ok "menu uses by-id identifiers" || bad "menu lacks by-id picking"
grep -q 'menu_password' "$menu" && bad "menu still asks for a password" || ok "menu asks for no password"
grep -q 'TARGETPW' "$menu" && bad "menu still carries a target password" || ok "menu carries no target password"
grep -q 'NETCONF_ARGS' "$menu" && bad "menu still preseeds destination networking" || ok "destination networking left to firstboot"
grep -q 'cp /etc/resolv.conf' "$menu" && bad "menu still copies DNS into destination" || ok "destination DNS left to firstboot"
grep -q -- '--repository' "$menu" && ok "menu passes a package repository" || bad "menu lacks repository selection"
grep -q 'usb-creator) continue' "$menu" && bad "menu skips only usb-creator" || ok "menu does not single out usb-creator"
grep -q 'list-targets' "$menu" && bad "menu enumerates engine targets" || ok "menu does not enumerate engine targets"
grep -q 'show_targets' "$menu" && bad "menu still has an engine-target viewer" || ok "no engine-target viewer remains"
grep -q 'List engine flavors' "$menu" && bad "menu still offers List engine flavors" || ok "List engine flavors removed"
grep -q '/usr/share/saphira/image/targets' "$menu" && bad "menu reads the engine target matrix" || ok "menu does not read the engine target matrix"
for pair in 'bios-saphira "BIOS Saphira"' 'uefi-saphira "UEFI Saphira"' 'bios-saphirad "BIOS SaphiraD"' 'uefi-saphirad "UEFI SaphiraD"'; do
	grep -qF "$pair" "$menu" && ok "menu offers ${pair%% *}" || bad "menu lacks ${pair%% *}"
done
for banned in bios-openrc bios-systemd uefi-openrc uefi-systemd usb-creator; do
	grep -q "$banned" "$menu" && bad "menu exposes $banned" || ok "menu does not expose $banned"
done
sed -n '/^target_label()/,/^}/p' "$menu" > "$work/target_label.sh"
# shellcheck disable=SC1090
. "$work/target_label.sh"
while IFS='|' read -r id label; do
	[ "$(target_label "$id")" = "$label" ] &&
		ok "target label $id is $label" || bad "target label $id wrong"
done <<'EOF'
bios-saphira|BIOS Saphira
uefi-saphira|UEFI Saphira
bios-saphirad|BIOS SaphiraD
uefi-saphirad|UEFI SaphiraD
EOF
grep -q 'setup "Setup network' "$menu" && ok "menu has Setup Network first" || bad "menu lacks Setup Network"
grep -q 'Cannot contact packages.saphira.vm2.uk. Please use Setup Network first.' "$menu" &&
	ok "menu refuses writes without the repository" || bad "menu lacks the unreachable message"
test -f "$root/files/saphira-image-creator-menu.service" &&
	ok "menu systemd service ships" || bad "menu systemd service missing"
test -f "$root/files/saphira-image-creator-menu.initd" &&
	ok "menu openrc service ships" || bad "menu initd missing"
test -f "$root/files/saphira-image-creator-recovery.service" &&
	ok "menu recovery service ships" || bad "menu recovery service missing"
grep -q '^OnFailure=saphira-image-creator-recovery.service' "$root/files/saphira-image-creator-menu.service" &&
	ok "menu failure starts recovery console" || bad "menu has no recovery fallback"
grep -q '^Restart=on-failure' "$root/files/saphira-image-creator-menu.service" &&
	ok "menu restarts on failure" || bad "menu does not restart on failure"
grep -q '^TTYPath=/dev/tty1' "$root/files/saphira-image-creator-recovery.service" &&
	ok "recovery console owns tty1" || bad "recovery console lacks tty1"
grep -q '^ExecStart=/bin/sh' "$root/files/saphira-image-creator-recovery.service" &&
	ok "recovery console is a shell" || bad "recovery console is not a shell"
grep -q 'Conflicts=.*saphira-image-creator-menu.service' "$root/files/saphira-image-creator-recovery.service" &&
	ok "recovery console displaces failed menu" || bad "recovery console lacks menu conflict"
grep -q 'for unit in saphira-firstboot-image.service saphira-firstboot.service saphira-install-menu.service getty@tty1.service' "$tool" &&
	ok "engine mask list leaves recovery alone" || bad "engine mask list changed"
grep -q 'image-creator-appliance' "$tool" && ok "engine knows the appliance profile" || bad "engine lacks appliance branch"
grep -q 'image-installer-appliance' "$tool" && ok "engine knows the installer profile" || bad "engine lacks installer branch"
grep -q 'saphira-image-creator-menu.service' "$tool" && ok "engine enables the creator menu" || bad "engine never enables the creator menu"
grep -q 'getty@tty1.service' "$tool" && ok "engine displaces tty1 getty" || bad "engine leaves tty1 getty"
grep -q 'finalize_appliance_repository' "$tool" && ok "engine finalizes the appliance repository" || bad "engine lacks repository finalizer"
grep -q 'install_appliance_network' "$tool" && ok "engine installs appliance network" || bad "engine lacks appliance network"
grep -q '80-saphira-wired-dhcp.network' "$tool" && ok "engine carries the wired DHCP default" || bad "engine lacks wired DHCP default"

printf '%s\n' '# creator menu flow against stubs'

stubdir=$work/stub
mkdir -p "$stubdir/bin"
cat > "$stubdir/bin/dialog" <<'EOF'
#!/bin/sh
printf 'dialog %s\n' "$*" >> "$STUB_LOG/calls"
mode=
while test $# -gt 0; do
	case $1 in
	--menu|--inputbox|--passwordbox) mode=input ;;
	--yesno|--msgbox) exit "${STUB_YESNO:-0}" ;;
	--backtitle|--title) shift 2; continue ;;
	0) ;;
	esac
	shift
done
if [ "$mode" = input ]; then
	answer=$(head -1 "$STUB_LOG/answers")
	tail -n +2 "$STUB_LOG/answers" > "$STUB_LOG/answers.new"
	mv "$STUB_LOG/answers.new" "$STUB_LOG/answers"
	printf '%s' "$answer" >&2
fi
exit 0
EOF
cat > "$stubdir/bin/saphira-image" <<'EOF'
#!/bin/sh
printf 'image %s\n' "$*" >> "$STUB_LOG/calls"
if [ "$1" = list-targets ]; then
	printf 'image list-targets\n' >> "$STUB_LOG/calls"
	exit 1
fi
exit 0
EOF
cat > "$stubdir/bin/saphira-install-plan" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$stubdir/bin/dialog" "$stubdir/bin/saphira-image" "$stubdir/bin/saphira-install-plan"
# create, bios-saphira, ext4, hostname, confirm, destroy. The destination
# must stay locked-root so ordinary firstboot owns credentials/networking.
printf 'create\nbios-saphira\next4\ntesthost\n' > "$stubdir/answers"
: > "$stubdir/calls"
STUB_LOG=$stubdir SAPHIRA_CREATOR_DIALOG=dialog SAPHIRA_CREATOR_TTY=/dev/null \
PATH="$stubdir/bin:/usr/bin:/bin" SAPHIRA_CREATOR_DISK=/dev/disk/by-id/usb-Test \
SAPHIRA_CREATOR_PING=/bin/true SAPHIRA_CREATOR_NOEXEC=1 SAPHIRA_CREATOR_ONESHOT=1 \
sh "$menu" > "$stubdir/out.txt" 2>&1 ||
	bad "menu flow exit: $(tail -2 "$stubdir/out.txt")"
target_menu=$(grep 'Destination system' "$stubdir/calls" 2>/dev/null || true)
for label in 'BIOS Saphira' 'UEFI Saphira' 'BIOS SaphiraD' 'UEFI SaphiraD'; do
	printf '%s\n' "$target_menu" | grep -qF "$label" &&
		ok "target menu offers $label" || bad "target menu lacks $label"
done
for banned in bios-openrc bios-systemd uefi-openrc uefi-systemd; do
	printf '%s\n' "$target_menu" | grep -q "$banned" &&
		bad "target menu offers $banned" || ok "target menu hides $banned"
done
printf '%s\n' "$target_menu" | grep -q 'usb-' &&
	bad "installer target offered" || ok "installer targets hidden"
grep -q 'image list-targets' "$stubdir/calls" 2>/dev/null &&
	bad "menu enumerated engine targets" || ok "menu did not enumerate engine targets"
grep -q 'System: BIOS Saphira' "$stubdir/calls" &&
	ok "confirmation names the destination product" || bad "confirmation lacks the product name"
grep -q 'NOEXEC saphira-image install-to-disk --target bios-saphira --device /dev/disk/by-id/usb-Test --hostname testhost --repository https://packages.saphira.vm2.uk/hatched --rootfs ext4' "$stubdir/out.txt" &&
	ok "menu drives engine with flavor, by-id device, hostname, repository, rootfs" ||
	bad "menu engine command wrong: $(grep NOEXEC "$stubdir/out.txt" || echo none)"
grep -q 'NOEXEC.*--preview' "$stubdir/out.txt" &&
	ok "menu previews before writing" || bad "menu skips preview"
grep -q 'SAPHIRA_ROOT_PASSWORD' "$stubdir/calls" "$stubdir/out.txt" 2>/dev/null &&
	bad "password variable reached the engine" || ok "destination stays locked-root for firstboot"

# Abort path: "no" at first confirmation writes nothing.
printf 'create\nbios-saphira\next4\ntesthost2\n' > "$stubdir/answers"
: > "$stubdir/calls"
STUB_YESNO=1 STUB_LOG=$stubdir SAPHIRA_CREATOR_DIALOG=dialog SAPHIRA_CREATOR_TTY=/dev/null \
PATH="$stubdir/bin:/usr/bin:/bin" SAPHIRA_CREATOR_DISK=/dev/disk/by-id/usb-Test \
SAPHIRA_CREATOR_PING=/bin/true SAPHIRA_CREATOR_NOEXEC=1 SAPHIRA_CREATOR_ONESHOT=1 \
sh "$menu" >/dev/null 2>&1 && bad "abort accepted" || ok "abort refused"
grep -q 'install-to-disk' "$stubdir/calls" 2>/dev/null && bad "abort ran engine" || ok "abort clean"

# Unreachable repository: write is refused with the exact message.
printf 'create\nbios-saphira\next4\ntesthost3\n' > "$stubdir/answers"
: > "$stubdir/calls"
STUB_LOG=$stubdir SAPHIRA_CREATOR_DIALOG=dialog SAPHIRA_CREATOR_TTY=/dev/null \
PATH="$stubdir/bin:/usr/bin:/bin" SAPHIRA_CREATOR_DISK=/dev/disk/by-id/usb-Test \
SAPHIRA_CREATOR_PING=/bin/false SAPHIRA_CREATOR_NOEXEC=1 SAPHIRA_CREATOR_ONESHOT=1 \
sh "$menu" > "$stubdir/offline.txt" 2>&1 ||
	bad "offline flow exit: $(tail -2 "$stubdir/offline.txt")"
grep -q 'Cannot contact packages.saphira.vm2.uk. Please use Setup Network first.' "$stubdir/calls" &&
	ok "offline write refused with the exact message" || bad "offline message wrong"
grep -q 'install-to-disk' "$stubdir/calls" 2>/dev/null && bad "offline ran engine" || ok "offline clean"

# Setup Network flow against stubs: setup, dhcp, back.
printf 'setup\ndhcp\nback\n' > "$stubdir/answers"
: > "$stubdir/calls"
cat > "$stubdir/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$STUB_LOG/calls"
exit 0
EOF
cat > "$stubdir/bin/ip" <<'EOF'
#!/bin/sh
printf 'ip %s\n' "$*" >> "$STUB_LOG/calls"
exit 0
EOF
cat > "$stubdir/bin/ping-ok" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$stubdir/bin/systemctl" "$stubdir/bin/ip" "$stubdir/bin/ping-ok"
STUB_LOG=$stubdir SAPHIRA_CREATOR_DIALOG=dialog SAPHIRA_CREATOR_TTY=/dev/null \
PATH="$stubdir/bin:/usr/bin:/bin" SAPHIRA_CREATOR_DISK=/dev/disk/by-id/usb-Test \
SAPHIRA_CREATOR_PING="$stubdir/bin/ping-ok" SAPHIRA_CREATOR_IP="$stubdir/bin/ip" \
SAPHIRA_CREATOR_SYSTEMCTL="$stubdir/bin/systemctl" SAPHIRA_CREATOR_NOEXEC=1 SAPHIRA_CREATOR_ONESHOT=1 \
sh "$menu" > "$stubdir/setup.txt" 2>&1 ||
	bad "setup flow exit: $(tail -2 "$stubdir/setup.txt")"
grep -q 'restart systemd-networkd' "$stubdir/calls" 2>/dev/null &&
	ok "setup dhcp restarts networkd" || bad "setup dhcp did not restart networkd"
grep -q 'packages.saphira.vm2.uk is reachable' "$stubdir/calls" 2>/dev/null &&
	ok "setup reports reachability" || bad "setup reachability missing"
grep -q 'install-to-disk' "$stubdir/calls" 2>/dev/null && bad "setup ran engine" || ok "setup writes nothing"

printf 'image-creator-appliance: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
