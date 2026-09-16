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

[ "$#" -eq 1 ] || die "usage: $0 OUTDIR"
out=$1
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
for tree in /usr/src/linux-*/; do
	[ -d "$tree" ] || continue
	base=${tree%/}
	base=${base#/usr/src/}
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
	case $kver in
		''|*[!0-9.]*)
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
