#!/bin/sh
# stage-kmod-input.sh — assemble the /input staging directory for kernel
# module recipes (nvidia-open-*, saphira-zfs-*) from the built kernel trees
# on this host.
#
# Usage: /recipes/saphira-kernel/files/stage-kmod-input.sh OUTDIR
# (absolute path: works from any cwd; for the whole set in one go see
# build-kmod-set.sh beside this script)
#
# Discovers kmod-ready trees itself (no version list to rot): any
# /usr/src/linux-<kver>/ or /usr/src/linux-<kver>-saphira/ with a
# Makefile and a BUILT scripts/sign-file is staged as
# <OUTDIR>/linux-<kver>/. The -saphira suffix marks the APK-owned
# prepared tree shipped by saphira-kernel (whose
# /lib/modules/<release>/build points at it); it wins when both forms
# exist for one version, so a stray unpacked tree can never shadow the
# packaged tree. Trees that are not ready are skipped with a warning;
# kmod recipes still fail closed per kernel. Exits non-zero only when
# nothing was staged at all.
#
# Staging is by bind-mount (trees live on a different filesystem than
# /build, so hardlink farms are impossible and full copies waste
# gigabytes): existing mounts under OUTDIR are refreshed, stale ones
# removed. Unmount when the builds are done, e.g.:
#   for d in OUTDIR/linux-*/; do sudo umount "$d"; done; rmdir OUTDIR/linux-*
# Needs sudo for the mounts.
#
# The module signing key is NOT staged here: the builder exposes the
# canonical host key read-only inside the build namespace itself
# (SAPHIRA_MODULE_KEY, fixed path /keys/module-signing.pem). No secret
# key copies ever live under /build.
#
# Afterwards: buildpkg <kmod-recipe> OUTDIR
# (e.g. for k in 7.1.5 7.2.2; do buildpkg nvidia-open-$k OUTDIR; done)

set -eu

die()
{
	printf 'stage-kmod-input: %s\n' "$*" >&2
	exit 1
}

# Effective settings of a .config: comments and blank lines carry no
# meaning, and generated order must not matter, so strip and sort.
effective_settings()
{
	sed -e 's/[[:space:]]*$//' "$1" 2>/dev/null |
		grep -vE '^[[:space:]]*(#|$)' |
		LC_ALL=C sort
}

# A tree is only fit to build external modules against if it was
# configured EXACTLY as the published kernel is. This is checked on
# content, never on mtime or directory name, because neither means
# anything here: a tree left over from an older pkgrel keeps its
# timestamp and its name while disagreeing with the running kernel.
#
# The check has to exist at all because these kernels build with
# CONFIG_MODVERSIONS unset. Without symbol CRCs, vermagic is just the
# upstream version -- "7.2.2" matches every 7.2.2 pkgrel -- so a module
# built against the wrong tree is ACCEPTED by the loader rather than
# rejected. It then fails quietly: different inlined decisions, a
# different exported-symbol set (a config key that moved y->m stops
# exporting to modules), a different CONFIG_PREFIX_SYMBOLS, and a
# different CONFIG_MODULE_SIG_KEY. Silent ABI mismatch is the failure
# mode that matters here, so fail closed instead of staging a guess.
config_matches_published()
{
	_tree=$1
	_canon=$2
	[ -f "$_tree/.config" ] || return 1
	a=$(effective_settings "$_tree/.config")
	b=$(effective_settings "$_canon")
	[ "$a" = "$b" ]
}

[ "$#" -eq 1 ] || die "usage: $0 OUTDIR"
out=$1
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Roots are overridable only so the provenance gate can be tested against
# fixtures instead of the live host. Defaults are the real paths.
src_root=${SAPHIRA_KMOD_SRC_ROOT:-/usr/src}
boot_root=${SAPHIRA_KMOD_BOOT_ROOT:-/boot}
key_src=${SAPHIRA_MODULE_KEY:-/etc/saphira/keys/module-signing.pem}

[ -f "$key_src" ] || die "module signing key missing: $key_src"
mkdir -p "$out"

# Refresh managed mounts first: unmount anything still bound under
# OUTDIR (stale mounts would shadow fresh trees), then drop mountpoints
# for kernels that no longer exist. Never rm -rf a mount: unmount,
# then rmdir only (fails on non-empty, which is the safe direction).
for dir in "$out"/linux-*/; do
	[ -d "$dir" ] || continue
	if mountpoint -q "$dir" 2>/dev/null; then
		sudo umount "$dir" || die "cannot unmount stale $dir"
	fi
	rmdir "$dir" 2>/dev/null || {
		printf 'stage-kmod-input: warning: leaving non-empty %s alone (not mount-managed?)\n' "$dir" >&2
	}
done

staged=0
skipped=""
candidates=""
for tree in "$src_root"/linux-*/; do
	[ -d "$tree" ] || continue
	base=${tree%/}
	base=${base#"$src_root"/}
	rest=${base#linux-}
	[ "$rest" != "$base" ] || {
		skipped="$skipped ${base}(bad-name)"
		continue
	}
	suffix=""
	case $rest in
		*-saphira)
			suffix="-saphira"
			kver=${rest%-saphira}
			;;
		*)
			kver=$rest
			;;
	esac
	# Release candidates ride along: 7.3-rc1 is a shipped kernel line
	# with per-kernel kmod recipes waiting (saphira-zfs-7.3-rc1,
	# nvidia-open-7.3-rc1, saphira-drbd9-7.3-rc1), but the old guard
	# below skipped it as bad-name, so no rc kmod could ever stage.
	# Anything else non-numeric is still refused.
	case $kver in
		[0-9][0-9.]*)
			;;
		[0-9][0-9.]*-rc[0-9]*)
			case $kver in
				*[!0-9.A-Za-z_-]*|*..*) skipped="$skipped ${kver}(bad-name)"; continue ;;
			esac
			;;
		*)
			skipped="$skipped ${kver}(bad-name)"
			continue
			;;
	esac
	if [ ! -f "$tree/Makefile" ]; then
		skipped="$skipped $kver(no-Makefile)"
		continue
	fi
	if [ ! -x "$tree/scripts/sign-file" ]; then
		skipped="$skipped $kver(sign-file-not-built)"
		continue
	fi
	# Fail closed unless the tree is provably configured as the published
	# kernel for this version is. A stale tree is reported, never staged.
	# The authority is the config the PUBLISHED kernel package ships
	# (/boot/config-<kver>-akadata), not the recipe's template: the
	# template is an input to "make olddefconfig", so the built config
	# legitimately differs from it (toolchain version, symbols the
	# Kconfig tree drops or renames). The tree and the running kernel
	# must agree with EACH OTHER, and that shared file is what says so.
	published=$boot_root/config-$kver-akadata
	if [ ! -f "$published" ]; then
		skipped="$skipped $kver(no-published-config)"
		continue
	fi
	if ! config_matches_published "$tree" "$published"; then
		skipped="$skipped $kver(config-not-published-$kver)"
		continue
	fi
	[ -r "$tree/include/config/kernel.release" ] || {
		skipped="$skipped $kver(no-kernel-release)"
		continue
	}
	treerel=$(cat "$tree/include/config/kernel.release")
	if [ "$treerel" != "$kver" ]; then
		# Release candidates report a three-part release (7.3.0-rc1)
		# for a two-part tree version (7.3-rc1); that exact mapping is
		# accepted because the kmod recipes address the tree by KVER_SHORT
		# while installing under the Makefile-derived KREL. Anything else
		# is still a mismatch.
		rc_base=${kver%-rc*}
		rc_n=${kver##*-rc}
		if [ "$rc_base" = "$kver" ] || [ "$treerel" != "$rc_base.0-rc$rc_n" ]; then
			skipped="$skipped $kver(release-$treerel)"
			continue
		fi
	fi
	candidates="$candidates $kver:$suffix:$tree"
done
saphira_kvers=""
for entry in $candidates; do
	kver=${entry%%:*}
	rest=${entry#*:}
	suffix=${rest%%:*}
	[ "$suffix" = "-saphira" ] || continue
	case " $saphira_kvers " in
		*" $kver "*) ;;
		*) saphira_kvers="$saphira_kvers $kver" ;;
	esac
done
for entry in $candidates; do
	kver=${entry%%:*}
	rest=${entry#*:}
	suffix=${rest%%:*}
	tree=${rest#*:}
	if [ -z "$suffix" ]; then
		case " $saphira_kvers " in
			*" $kver "*)
				skipped="$skipped $kver(plain-shadowed-by-saphira)"
				continue
				;;
		esac
	fi
	mkdir -p "$out/linux-$kver"
	sudo mount --bind "$tree" "$out/linux-$kver" ||
		die "cannot bind-mount $tree (sudo required)"
	staged=$((staged + 1))
	printf 'stage-kmod-input: staged linux-%s from %s\n' "$kver" "$tree"
done

for stale_key in saphira-module.pem module-signing.pem; do
if [ -f "$out/$stale_key" ]; then
	printf 'stage-kmod-input: WARNING: stale staged key copy %s (no longer used - builder exposes the canonical key; remove it)\n' "$out/$stale_key" >&2
fi
done
for note in $skipped; do
	printf 'stage-kmod-input: warning: skipped kernel tree %s\n' "$note" >&2
done
[ "$staged" -gt 0 ] || die "no kmod-ready kernel trees found under /usr/src"
printf 'stage-kmod-input: ready: %d kernel tree(s) in %s\n' "$staged" "$out"
printf 'stage-kmod-input: unmount when done; see script header\n'
