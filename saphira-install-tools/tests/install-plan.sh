#!/bin/sh
# saphira-install-plan suite: manifest validation matrix, secrets
# refusal, kernel-support proofs, determinism. Pure file logic: no
# disk writes, no network, no root.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=$here/../files/saphira-install-plan
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/install-plan-test-$$
mkdir -p "$testdir/profiles"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf 'saphira-openrc\n' > "$testdir/profiles/saphira-openrc"
printf 'saphirad-systemd\n' > "$testdir/profiles/saphirad-systemd"
printf 'CONFIG_EXT4_FS=y\n' > "$testdir/kext4.config"
printf 'CONFIG_EXT4_FS=y\nCONFIG_XFS_FS=y\n' > "$testdir/kxfs.config"

mkmanifest()
{
	name=$1
	shift
	{
		printf 'PLAN_VERSION=1\nFIRMWARE=auto\nINIT=systemd\n'
		printf 'ROOTFS=ext4\nLAYOUT=direct\nDISK=/dev/sda\n'
		printf 'ROLE=base\nPROFILE=saphirad-systemd\n'
		printf 'REPOSITORY=https://packages.saphira.vm2.uk/hatched\n'
		printf 'HOSTNAME=saphira-new\n'
	} > "$testdir/$name"
	# Extras override the base (replace) or extend it (new keys):
	# manifests refuse duplicates, so the suite must too.
	for extra in "$@"; do
		k=${extra%%=*}
		if grep -q "^$k=" "$testdir/$name"; then
			sed -i "s|^$k=.*|$extra|" "$testdir/$name"
		else
			printf '%s\n' "$extra" >> "$testdir/$name"
		fi
	done
}

run()
{
	SAPHIRA_PROFILE_ROOT="$testdir/profiles" sh "$tool" "$@"
}

# baseline: valid manifest validates and shows deterministically
mkmanifest good
run validate "$testdir/good" >/dev/null 2>&1 && ok validate-good || bad validate-good
run show "$testdir/good" > "$testdir/show-1.txt" 2>&1
run show "$testdir/good" > "$testdir/show-2.txt" 2>&1
cmp -s "$testdir/show-1.txt" "$testdir/show-2.txt" && ok show-stable || bad show-unstable
grep -q 'destructive: /dev/sda will be repartitioned' "$testdir/show-1.txt" && ok show-warns-destructive || bad show-no-warning
grep -q 'needs: kernel EXT4_FS=y (unproven' "$testdir/show-1.txt" && ok show-needs-unproven || bad show-no-needs

# kernel support proofs
run validate --kernel-config "$testdir/kext4.config" "$testdir/good" >/dev/null 2>&1 && ok kconfig-ext4-proven || bad kconfig-ext4-refused
mkmanifest xfs ROOTFS=xfs
run validate --kernel-config "$testdir/kext4.config" "$testdir/xfs" 2>/dev/null && bad kconfig-xfs-unproven-accepted || ok kconfig-xfs-fails-closed
run validate --kernel-config "$testdir/kxfs.config" "$testdir/xfs" >/dev/null 2>&1 && ok kconfig-xfs-proven || bad kconfig-xfs-refused

# zfs matrix
mkmanifest zfsgone ROOTFS=zfs LAYOUT=zpool POOL=tank DATASET=tank/ROOTS/saphirad BOOT_SIZE=1G
run validate "$testdir/zfsgone" >/dev/null 2>&1 && ok validate-zfs || bad validate-zfs
run show "$testdir/zfsgone" 2>&1 | grep -q '/boot ext4 1G (GRUB reads this, never ZFS)' && ok show-zfs-boot-split || bad show-zfs-no-split
run show "$testdir/zfsgone" 2>&1 | grep -q 'needs: ZFS kmod' && ok show-zfs-needs-kmod || bad show-zfs-no-kmod
mkmanifest zfsdirect ROOTFS=zfs LAYOUT=direct POOL=tank DATASET=tank/ROOTS/x BOOT_SIZE=1G
run validate "$testdir/zfsdirect" 2>/dev/null && bad zfs-direct-accepted || ok zfs-direct-refused
mkmanifest zfsnods ROOTFS=zfs LAYOUT=zpool
run validate "$testdir/zfsnods" 2>/dev/null && bad zfs-nopool-accepted || ok zfs-nopool-refused
mkmanifest zfsextra POOL=tank
run validate "$testdir/zfsextra" 2>/dev/null && bad pool-with-ext4-accepted || ok pool-with-ext4-refused

# lvm matrix
mkmanifest lvmgood ROOTFS=ext4 LAYOUT=lvm VG=saphira LV_SIZE=%FREE
run validate "$testdir/lvmgood" >/dev/null 2>&1 && ok validate-lvm || bad validate-lvm
run show "$testdir/lvmgood" 2>&1 | grep -q 'VG saphira -> LV root ext4 %FREE' && ok show-lvm-sketch || bad show-lvm-no-sketch
mkmanifest lvmzfs ROOTFS=zfs LAYOUT=lvm VG=saphira LV_SIZE=20G POOL=tank DATASET=tank/ROOTS/x BOOT_SIZE=1G
run validate "$testdir/lvmzfs" 2>/dev/null && bad lvm-zfs-accepted || ok lvm-zfs-refused
mkmanifest lvmnolv ROOTFS=ext4 LAYOUT=lvm
run validate "$testdir/lvmnolv" 2>/dev/null && bad lvm-novg-accepted || ok lvm-novg-refused

# secrets, unknown keys, malformed lines
mkmanifest secret ROOT_PASSWORD=hunter2
run validate "$testdir/secret" 2>/dev/null && bad secret-accepted || ok secret-refused
mkmanifest mystery FROBNICATE=yes
run validate "$testdir/mystery" 2>/dev/null && bad unknown-key-accepted || ok unknown-key-refused
printf 'NOT-A-PAIR\n' > "$testdir/malformed"
run validate "$testdir/malformed" 2>/dev/null && bad malformed-accepted || ok malformed-refused
printf 'PLAN_VERSION=1\nROLE=base\nROLE=docker\n' > "$testdir/dupkey"
run validate "$testdir/dupkey" 2>/dev/null && bad duplicate-accepted || ok duplicate-refused

# value domains
mkmanifest badfw FIRMWARE=coreboot
run validate "$testdir/badfw" 2>/dev/null && bad firmware-accepted || ok firmware-refused
mkmanifest badrole ROLE=desktop
run validate "$testdir/badrole" 2>/dev/null && bad role-accepted || ok role-refused
mkmanifest badrepo REPOSITORY=http://plain.example/
run validate "$testdir/badrepo" 2>/dev/null && bad repo-accepted || ok repo-refused
mkmanifest badhost HOSTNAME='bad host!'
run validate "$testdir/badhost" 2>/dev/null && bad hostname-accepted || ok hostname-refused
mkmanifest baddisk DISK=sda
run validate "$testdir/baddisk" 2>/dev/null && bad disk-accepted || ok disk-refused
mkmanifest badprof PROFILE='../evil'
run validate "$testdir/badprof" 2>/dev/null && bad profile-accepted || ok profile-refused
mkmanifest badver PLAN_VERSION=2
run validate "$testdir/badver" 2>/dev/null && bad version-accepted || ok version-refused

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all install-plan cases pass\n'
