#!/bin/sh

# Recipe metadata rules: static assertions over recipe.sh files that
# encode incident-driven invariants (no build required). Each case names
# the incident it locks in. Sourcing happens in a subshell so recipe
# top-level assignments never leak into the harness.
#
# usage: recipe-rules.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

recipe_var()
{
	(
		. "$source_root/$1/recipe.sh"
		eval "printf '%s' \"\$$2\""
	)
}

# apk version grammar: a pkgver may not contain a '.' immediately followed
# by a letter. PEP 440 dot-suffixes (2.9.0.post0, 1.0.dev1, 1.0.rc1) are
# rejected by apk at mkpkg time ("info field 'version' has invalid value"),
# which surfaces only at package construction, long after the recipe looked
# fine. The apk-native spelling is the '_' suffix form (2.9.0_p0,
# 2026.09.08_rc1, 7.3_rc1); apk's patch level '_p<N>' sorts above the base
# exactly as a post-release does. Incident: python-dateutil 2.9.0.post0 and
# python-pytz 2026.3.post1 blocked ten OpenStack packages at makepkg.
for _r in "$source_root"/*/recipe.sh; do
	_v=$(sed -n 's/^pkgver=//p' "$_r")
	case "$_v" in
	*.[A-Za-z]*)
		printf '%s\n' "${_r#"$source_root"/}: pkgver '$_v' has a '.' before a letter, which apk rejects (use the '_' suffix form, e.g. 2.9.0_p0 / 2026.09.08_rc1)" >&2
		exit 1
		;;
	esac
done

# Incident: nginx 1.30.4-r4 configure failed its libxslt probe with
# libxslt-dev installed (retained /build/nginx.buildpkg log), because
# libxml2 headers were absent from the build root. libxslt headers
# include libxml2 headers, so libxslt-dev must carry libxml2-dev via
# the Alpine-style depends_dev convention (curl/libzip precedent).
case " $(recipe_var libxslt depends_dev) " in
	*" libxml2-dev "*) ;;
	*)
		printf '%s\n' 'libxslt depends_dev is missing libxml2-dev (nginx xslt probe regresses)' >&2
		exit 1
		;;
esac

# mariadb-server owns the mysql service identity (UID/GID 106,
# convergent with the base seed): the fragment must exist and declare
# exactly that binding, or installs fail closed on AZ2 targets.
mysql_fragment=$source_root/mariadb-server/files/accounts.d/mariadb-server
[ -f "$mysql_fragment" ] || {
	printf '%s\n' 'mariadb-server fragment is missing (mysql identity unowned)' >&2
	exit 1
}
grep -Eq '^user mysql 106 mysql /var/lib/mysql /sbin/nologin$' "$mysql_fragment" || {
	printf '%s\n' 'mariadb-server fragment does not declare user mysql 106' >&2
	exit 1
}
grep -Eq '^group mysql 106$' "$mysql_fragment" || {
	printf '%s\n' 'mariadb-server fragment does not declare group mysql 106' >&2
	exit 1
}

# nginx carries the Arch-parity dynamic module set; sub_filter is
# mandatory for AZ2 realtime-price rewriting and must never go missing.
# Third-party sources must be vendored under files/ (no floating fetches).
nginx_recipe=$source_root/nginx/recipe.sh
for flag in \
	--with-http_sub_module \
	--with-http_geoip_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_perl_module=dynamic \
	--with-http_xslt_module=dynamic \
	--with-stream=dynamic \
	'--add-dynamic-module="$SRC/modules/memc"' \
	'--add-dynamic-module="$SRC/modules/cache_purge"'; do
	grep -Fq -- "$flag" "$nginx_recipe" || {
		printf '%s\n' "nginx recipe is missing module flag: $flag" >&2
		exit 1
	}
done
for module_tarball in memc-0.21.tar.gz cache-purge-2.3.tar.gz; do
	[ -f "$source_root/nginx/files/$module_tarball" ] || {
		printf '%s\n' "nginx module source is not vendored: $module_tarball" >&2
		exit 1
	}
done
[ -f "$source_root/gd/files/libgd-2.3.3.tar.xz" ] || {
	printf '%s\n' 'gd source is not vendored (nginx image_filter has no headers)' >&2
	exit 1
}

# lldpd owns its privilege-separation identity (_lldpd:147,
# convergent with nothing - it must be a fresh reservation; it was 124
# until 124 was found to be hostapd's).
lldpd_fragment=$source_root/lldpd/files/accounts.d/lldpd
[ -f "$lldpd_fragment" ] || {
	printf '%s\n' 'lldpd fragment is missing (_lldpd identity unowned)' >&2
	exit 1
}
grep -Eq '^user _lldpd 147 _lldpd /var/run/lldpd /sbin/nologin$' "$lldpd_fragment" || {
	printf '%s\n' 'lldpd fragment does not declare user _lldpd 147' >&2
	exit 1
}
grep -Eq '^group _lldpd 147$' "$lldpd_fragment" || {
	printf '%s\n' 'lldpd fragment does not declare group _lldpd 147' >&2
	exit 1
}

# FRR owns its service identity (frr:125, a fresh reservation for
# the new routing suite).
frr_fragment=$source_root/frr/files/accounts.d/frr
[ -f "$frr_fragment" ] || {
	printf '%s\n' 'frr fragment is missing (frr identity unowned)' >&2
	exit 1
}
grep -Eq '^user frr 125 frr /var/run/frr /sbin/nologin$' "$frr_fragment" || {
	printf '%s\n' 'frr fragment does not declare user frr 125' >&2
	exit 1
}
grep -Eq '^group frr 125$' "$frr_fragment" || {
	printf '%s\n' 'frr fragment does not declare group frr 125' >&2
	exit 1
}

# dhcpcd owns its service identity (dhcpcd:104). It drops privileges to
# this user before doing anything else and refuses to run without it, so
# an image carrying no such account could not run DHCP at all. The gap
# was invisible because dhcpcd daemonises: the parent exits 0 and the
# privileged child dies afterwards, so the failure never reached the
# exit status anybody checked and nothing red appeared in the boot log.
dhcpcd_fragment=$source_root/dhcpcd/files/accounts.d/dhcpcd
[ -f "$dhcpcd_fragment" ] || {
	printf '%s\n' 'dhcpcd fragment is missing (dhcpcd identity unowned; DHCP cannot start)' >&2
	exit 1
}
grep -Eq '^user dhcpcd 104 dhcpcd /var/lib/dhcpcd /sbin/nologin$' "$dhcpcd_fragment" || {
	printf '%s\n' 'dhcpcd fragment does not declare user dhcpcd 104' >&2
	exit 1
}
grep -Eq '^group dhcpcd 104$' "$dhcpcd_fragment" || {
	printf '%s\n' 'dhcpcd fragment does not declare group dhcpcd 104' >&2
	exit 1
}
grep -Eq '^dir /var/lib/dhcpcd 0755 dhcpcd dhcpcd$' "$dhcpcd_fragment" || {
	printf '%s\n' 'dhcpcd fragment does not converge its state directory (dropped-privilege client cannot store leases)' >&2
	exit 1
}
# The base seed and the fragment must agree exactly: the publish gate
# refuses a fragment that drifts from the seed, so a home-directory
# disagreement here is a broken fresh install, not a cosmetic diff.
seed_home=$(awk '$1 == "dhcpcd" && $2 == "user" { print $5 }' "$source_root/saphira-baselayout/files/accounts.tsv")
fragment_home=$(sed -n 's/^user dhcpcd [0-9][0-9]* dhcpcd \([^ ]*\) .*/\1/p' "$dhcpcd_fragment")
if test -n "$seed_home" && test "$seed_home" = "$fragment_home"; then
	printf '%s\n' 'ok       dhcpcd base-seed and fragment identities agree'
else
	printf '%s\n' "dhcpcd seed home ($seed_home) disagrees with fragment home ($fragment_home)" >&2
	exit 1
fi
grep -q 'accounts.d/dhcpcd' "$source_root/dhcpcd/recipe.sh" || {
	printf '%s\n' 'dhcpcd recipe does not install its accounts.d fragment' >&2
	exit 1
}

# Declared service identities must not collide. Two packages claiming one
# uid is a silent identity conflict decided by install order.
identity_ids=$(cat "$source_root"/*/files/accounts.d/* 2>/dev/null |
	awk '/^user [^ ]+ [0-9]+ / { print $2, $3 }' |
	sort -k2,2n)
dup_ids=$(printf '%s\n' "$identity_ids" | awk '{ count[$2]++; names[$2]=names[$2] " " $1 }
	END { for (id in count) if (count[id] > 1) print id ":" names[id] }')
if [ -n "$dup_ids" ]; then
	printf 'FAIL: service identity uid collision: %s\n' "$dup_ids" >&2
	exit 1
fi
printf '%s\n' 'ok       no duplicate service identity uids'

# Historical identity claims must not collide with another package's
# current claims. The repository gate refuses a published union in
# which one id is claimed twice (e.g. a legacy sidecar asserting a
# uid some other package now owns: hand-provisioned local accounts
# have no standing against the published record). Mirror that rule
# here so it fails in-tree, before staging: for each legacy user/group
# entry, its uid (user namespace) and gid (group namespace) must be
# single-claimed tree-wide. Claims identical to the base seed converge
# silently (ground truth, not a package claim) and are exempt.
legacy_dup=$(cd "$source_root" && {
	seed_users=$(awk -F'\t' '$2 == "user" { print "u:"$3" "$1 }' saphira-baselayout/files/accounts.tsv 2>/dev/null)
	seed_groups=$(awk -F'\t' '$2 == "group" { print "g:"$3" "$1 }' saphira-baselayout/files/accounts.tsv 2>/dev/null)
	for frag in */files/accounts.d/*.legacy; do
		[ -e "$frag" ] || continue
		pkg=${frag%%/*}
		awk -v pkg="$pkg" '
			/^legacy user [^ ]+ [0-9]+ [0-9]+/ { print "u:"$4" "pkg":"$3; print "g:"$5" "pkg":"$3 }
			/^legacy group [^ ]+ [0-9]+/ { print "g:"$4" "pkg":"$3 }' "$frag"
	done
	for frag in */files/accounts.d/*; do
		case $frag in *.legacy) continue;; esac
		[ -e "$frag" ] || continue
		pkg=${frag%%/*}
		awk -v pkg="$pkg" '
			/^user [^ ]+ [0-9]+ / { print "u:"$3" "pkg":"$2 }
			/^group [^ ]+ [0-9]+/ { print "g:"$3" "pkg":"$2 }' "$frag"
	done
	printf '%s\n%s\n' "$seed_users" "$seed_groups" | awk '{ print $1" seed:"$2 }'
} 2>/dev/null | sort | awk '
	{ id[$1] = id[$1] " " $2 }
	END { for (k in id) { n = split(id[k], a, " "); ok = 1; for (i = 1; i <= n; i++) if (a[i] !~ /^seed:/ && a[i] != "") ok = 0;
		if (!ok) { m = 0; for (i = 1; i <= n; i++) if (a[i] !~ /^seed:/ && a[i] != "") m++; if (m > 1) print k ":" id[k] } } }')
if [ -n "$legacy_dup" ]; then
	printf 'FAIL: historical identity claim collides with a current claim: %s\n' "$legacy_dup" >&2
	exit 1
fi
printf '%s\n' 'ok       no historical identity claim collides'

# Man hierarchy navigability: every page carries all eight required
# sections, contains ASCII only (groff-clean output), and every
# `name (section)` reference anywhere resolves to a shipped page
# (following .so alias redirects). A dangling SEE ALSO is a broken
# documentation system.
man_dir=$source_root/saphira-docs/files
if [ -d "$man_dir" ]; then
	for page in "$man_dir"/*.[1578]; do
		[ -e "$page" ] || continue
		if [ "$(head -c 4 "$page")" = ".so " ]; then
			continue
		fi
		for section in NAME SYNOPSIS DESCRIPTION OPTIONS FILES "EXIT STATUS" EXAMPLES "SEE ALSO"; do
			grep -q "^\.SH $section\$" "$page" || {
				printf '%s\n' "man page $page is missing section: $section" >&2
				exit 1
			}
		done
		if LC_ALL=C grep -q "[^ -~	]" "$page"; then
			printf '%s\n' "man page $page contains non-ASCII bytes" >&2
			exit 1
		fi
	done
	for page in "$man_dir"/*.[1578]; do
		[ -e "$page" ] || continue
		refs=$(grep -oE '[A-Za-z0-9_.*+-]+ \([1578]\)' "$page" | sed 's/ (/-/;s/)//' || true)
		for ref in $refs; do
			name=${ref%-*}
			section=${ref##*-}
			target=$man_dir/$name.$section
			[ -e "$target" ] || {
				printf '%s\n' "man page $page references missing page: $name($section)" >&2
				exit 1
			}
			if [ "$(head -c 4 "$target")" = ".so " ]; then
				dest=$(sed -n 's/^\.so //p' "$target")
				# Installed layout (man8/name.8) and flat source
				# layout (name.8) both resolve; one must exist.
				[ -e "$man_dir/$dest" ] || [ -e "$man_dir/$(basename "$dest")" ] || {
					printf '%s\n' "man alias $target points nowhere: $dest" >&2
					exit 1
				}
			fi
		done
	done
fi

# man-db carries the musl //IGNORE fallback patch (manconv requests
# UTF-8//IGNORE on its last encoding guess; musl rejects the suffix
# with EINVAL - proven live) and applies it in the build.
[ -f "$source_root/man-db/files/musl-iconv-fallback.patch" ] || {
	printf '%s\n' 'man-db musl iconv patch is missing' >&2
	exit 1
}
grep -Fq 'musl-iconv-fallback.patch' "$source_root/man-db/recipe.sh" || {
	printf '%s\n' 'man-db recipe does not apply the musl iconv patch' >&2
	exit 1
}

# saphira-docs pulls its reader: `man <page>` must work where docs land.
case " $(recipe_var saphira-docs depends) " in
	*" man-db "*) ;;
	*)
		printf '%s\n' 'saphira-docs depends is missing man-db (dead pages)' >&2
		exit 1
		;;
esac

# Incident: verified upstream archives were staged in /tmp/batchN (wiped by
# the 2026-09-10 reboot before vendoring). The local recipe collection is
# self-contained: every fetchable (source=|vendor=, sha256=) pair must have
# its archive verified in <pkg>/files/ with a .sha256 sidecar, and the
# builder prefers it over any download. Public builders fetch via URLs.
check_base=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$check_base"
check_out=$check_base/recipe-rules-fetch-check.out
"$source_root/saphira-packager/files/fetch-vendor-sources" --check > "$check_out" 2>&1 || {
	printf '%s\n' "vendored-sources gate failed (see $check_out)" >&2
	exit 1
}
grep -q '^MISSING' "$check_out" && {
	printf '%s\n' "vendored-sources gate: archives MISSING from files/ (see $check_out)" >&2
	exit 1
}
rm -f "$check_out"

# Incident: same /tmp/batchN episode. Host /tmp is never Saphira scratch:
# no recipe may reference it (RPATH-leak detection patterns naming
# /var/tmp, and the sandbox HOME=/tmp comment, are the documented
# exceptions). Controller tools/tests moved to SAPHIRA_TMPDIR.
tmp_refs=$(grep -RnE '/tmp(/|"|$)' "$source_root"/*/recipe.sh 2>/dev/null \
	| grep -v 'RPATH\|RUNPATH\|HOME=/tmp\|/var/tmp' || true)
[ -z "$tmp_refs" ] || {
	printf '%s\n' "recipe /tmp references forbidden: $tmp_refs" >&2
	exit 1
}
tmp_tools=$(grep -Rn -- '--tmpfs\|mktemp[^"'"'"']*/tmp/' "$source_root/saphira-packager/files" "$source_root/saphira-packager/tests" 2>/dev/null \
	| grep -v 'build-ran\|recipe-rules.sh' || true)
[ -z "$tmp_tools" ] || {
	printf '%s\n' "controller /tmp usage forbidden: $tmp_tools" >&2
	exit 1
}

# Incident: min-r1 is a three-layer rule (resolvepkg refuses to plan r0,
# buildpkg-single refuses to stage r0, sign-apk-repo refuses staged r0 in
# multi-generation runs). The source layer: no recipe may declare pkgrel 0.
r0_recipes=$(grep -rln '^pkgrel=0$' "$source_root"/*/recipe.sh 2>/dev/null || true)
[ -z "$r0_recipes" ] || {
	printf '%s\n' "pkgrel 0 recipes forbidden: $r0_recipes" >&2
	exit 1
}

# Incident: dbus declared depends+makedepends on the full PID-1 systemd
# package, which silently dragged a different init onto an OpenRC host
# after an explicit removal (Egg: systemd deleted, dbus pulled it back,
# next upgrade collided on /sbin/init owned by openrc). Library
# consumers link systemd-libs/systemd-dev only; a packaged .service
# unit never justifies an init-system dependency. Both directions hold:
# no OpenRC-closure package may resolve full systemd transitively, and
# no systemd-closure package may resolve full openrc.
init_coupled=$(for recipe in "$source_root"/*/recipe.sh; do
	if awk '/^(depends|makedepends)="/ {
		print $0
		if ($0 ~ /"$/) next
		inblock = 1
		next
	}
	inblock {
		print $0
		if ($0 ~ /^"$/) inblock = 0
	}' "$recipe" | sed -e 's/systemd-libs/SYSTEMDLIBS/g; s/systemd-dev/SYSTEMDDEV/g' | grep -qw -e systemd -e openrc; then
		printf '%s\n' "$recipe"
	fi
done || true)
[ -z "$init_coupled" ] || {
	printf '%s\n' "init-system coupling forbidden (use systemd-libs/systemd-dev): $init_coupled" >&2
	exit 1
}
# The legal edge, locked: dbus links libsystemd.so.0, so it depends on
# the libs split - never the init package.
grep -Eq '^depends="[^"]*systemd-libs' "$source_root/dbus/recipe.sh" || {
	printf '%s\n' 'dbus must depend on systemd-libs (never full systemd)' >&2
	exit 1
}

# Incident: legacy sidecars steer install-blocked migrations, so a
# malformed or dangling sidecar is a broken repair path. Every
# accounts.d/*.legacy must sit beside its fragment, contain only
# well-formed legacy stanzas, and name only identities the sibling
# fragment declares (only declared identities qualify, enforced again
# at build and publish time).
for legacy in "$source_root"/*/files/accounts.d/*.legacy; do
	[ -f "$legacy" ] || continue
	frag=${legacy%.legacy}
	[ -f "$frag" ] || {
		printf '%s\n' "legacy sidecar without fragment: $legacy" >&2
		exit 1
	}
	bad_shape=$(grep -Ev '^#|^$' "$legacy" | grep -Ev '^legacy (user [A-Za-z0-9_.][A-Za-z0-9_.-]* [0-9]+ [0-9]+|group [A-Za-z0-9_.][A-Za-z0-9_.-]* [0-9]+)$' || true)
	[ -z "$bad_shape" ] || {
		printf '%s\n' "malformed legacy stanza in $legacy: $bad_shape" >&2
		exit 1
	}
	for legname in $(grep -Eo '^legacy (user|group) [A-Za-z0-9_.][A-Za-z0-9_.-]*' "$legacy" | awk '{print $3}'); do
		grep -Eq "^(user|group) $legname " "$frag" || {
			printf '%s\n' "legacy identity $legname in $legacy is not declared in $frag" >&2
			exit 1
		}
	done
done

# Incident: the accounts.d/systemd census drifted from the shipped
# sysusers.d declarations (imds and coredump missed) while production
# relied on them. systemd is sysusers-native now: the fragment carries
# only the sysusers stanza, fixed IDs live in the shipped confs, and
# post-install/post-upgrade run systemd-sysusers. This locks the full
# mapping so a new upstream identity cannot slip through unpinned.
sys_frag=$source_root/systemd/files/accounts.d/systemd
[ "$(grep -c '^sysusers$' "$sys_frag")" -eq 1 ] || {
	printf '%s\n' 'systemd fragment must carry exactly one sysusers stanza' >&2
	exit 1
}
grep -Eq '^(user|group|dir|file) ' "$sys_frag" && {
	printf '%s\n' 'systemd fragment must not duplicate sysusers declarations' >&2
	exit 1
}
for flag in \
	'-Dsystemd-journal-gid=131' \
	'-Dsystemd-network-uid=127' \
	'-Dsystemd-resolve-uid=128' \
	'-Dsystemd-timesync-uid=129' \
	'-Dsystemd-imds-uid=145'; do
	grep -Fq -- "$flag" "$source_root/systemd/recipe.sh" || {
		printf '%s\n' "systemd recipe is missing fixed-ID flag: $flag" >&2
		exit 1
	}
done
sys_patch=$source_root/systemd/files/sysusers-static-ids.patch
for pin in \
	'u! systemd-oom 130 ' \
	'u! systemd-coredump 144 '; do
	grep -Fq -- "$pin" "$sys_patch" || {
		printf '%s\n' "systemd static-ids patch is missing pin: $pin" >&2
		exit 1
	}
done
# Upstream coverage: every identity-declaring sysusers conf in the
# vendored source that installs under the recipe feature set must be
# pinned above. basic.conf is the pre-existing group menagerie (out
# of scope); systemd-remote.conf needs microhttpd (not a dependency,
# so it never installs - asserted below, revisit if that changes).
# Anything else unpinned fails closed here.
grep -qi microhttpd "$source_root/systemd/recipe.sh" && {
	printf '%s\n' 'systemd gained microhttpd: revisit systemd-remote.conf coverage' >&2
	exit 1
}
sys_src=$(ls "$source_root"/systemd/files/*.tar.gz | head -n 1)
sys_tmp=$check_base/recipe-rules-sysusers
rm -rf "$sys_tmp"
mkdir -p "$sys_tmp"
tar -xzf "$sys_src" -C "$sys_tmp" --wildcards '*/sysusers.d/*.conf' '*/sysusers.d/*.conf.in'
unpinned=""
for conf in "$sys_tmp"/*/sysusers.d/*.conf "$sys_tmp"/*/sysusers.d/*.conf.in; do
	[ -f "$conf" ] || continue
	base=$(basename "$conf" .in)
	base=${base%.conf}
	case $base in
		basic|systemd-remote) continue ;;
	esac
	grep -Eq '^(u|g|m)[! ]' "$conf" || continue
	case $base in
		systemd-journal|systemd-network|systemd-resolve|systemd-timesync|systemd-imds|systemd-oom|systemd-coredump) ;;
		*) unpinned="$unpinned $base" ;;
	esac
done
[ -z "$unpinned" ] || {
	printf '%s\n' "systemd sysusers confs without fixed IDs:$unpinned" >&2
	exit 1
}
rm -rf "$sys_tmp"

# --- profile pinning: two halves, deliberately checked separately ------------
#
# Saphira as a whole must NOT prevent a consumer from pinning. Someone
# deliberately holding an older kernel line, or keeping a system steady while
# a new one is validated, needs to be able to write package=version, and the
# mechanism must be there for them. So the profile expander keeps '=' legal.
#
# What we do is different, and is the half that is enforced here: OUR OWN
# profiles name bare packages and never pin. A pin in our profiles is a
# standing liability. It does not remove a bad outcome, it relocates the
# failure: when the pinned NVR is retired from the live index the entry
# becomes unresolvable, the package manager falls back, and the system lands
# on something nobody chose while the pin still reads as an intentional
# selection. That happened to saphira-kernel here.
#
# Checked in both directions, because each half has been got wrong once:
# removing the capability from the expander would only stop OTHER people
# pinning, and adding a pin to our profiles would reintroduce the fallback.
pin_refused=0
for expander in saphira-install-tools/files/saphira-bootstrap; do
	f="$source_root/$expander"
	[ -f "$f" ] || continue
	grep -q 'A-Za-z0-9._+=-' "$f" || {
		printf '%s\n' "profile expander refuses '=': consumers must be able to pin a version" >&2
		pin_refused=1
	}
done
[ "$pin_refused" -eq 0 ] || exit 1

pinned=""
for f in "$source_root"/saphira-install-tools/files/profiles/* \
	"$source_root"/saphira-image-creator/files/profiles/*; do
	[ -f "$f" ] || continue
	grep -nE '^[[:space:]]*[A-Za-z0-9._+-]+=[^=]' "$f" 2>/dev/null |
		while IFS= read -r hit; do
			printf 'our profile pins a version (we never do package=rver): %s: %s\n' \
				"${f#"$source_root"/}" "$hit" >&2
			echo x
		done | grep -q x && pinned=1
done
[ -z "$pinned" ] || exit 1

# Incident: linux2024 (OVMF/UEFI + QXL) showed a black screen after GRUB
# loaded 7.3-rc1, while BIOS/VGA hosts booted the same kernel. Root cause
# was a gap, not drift: no vendored config ever carried the EFI framebuffer
# console (VGA_CONSOLE covers BIOS only; UEFI has no VGA text mode), and
# nothing asserted the no-initramfs builtin set, so `make olddefconfig`
# could silently demote a required =y. The build gate below must stay wired
# into saphira-kernel recipe_build() right after olddefconfig.
kernel_recipe=$source_root/saphira-kernel/recipe.sh
grep -Fq 'check_no_initramfs_builtins' "$kernel_recipe" || {
	printf '%s\n' 'saphira-kernel recipe no longer invokes the no-initramfs builtin gate (UEFI console / builtin policy regresses silently)' >&2
	exit 1
}
[ -f "$source_root/saphira-kernel/files/check-no-initramfs-builtins.sh" ] || {
	printf '%s\n' 'no-initramfs builtin gate script missing from saphira-kernel/files' >&2
	exit 1
}

# Incident: systemd-262-r2 shipped upstream's merged-/usr helper defaults
# (split-usr removal) on a non-usrmerged system: no /sbin/init, and every
# mount unit failed on missing /usr/bin/mount, ending in an emergency mode
# whose /usr/sbin/sulogin was equally absent. The recipe pins Saphira's
# real helper paths via upstream's -D*-path options. Neither may silently
# revert to merged defaults.
systemd_recipe=$source_root/systemd/recipe.sh
for path_flag in \
	'-Dmount-path=/bin/mount' \
	'-Dumount-path=/bin/umount' \
	'-Dsulogin-path=/sbin/sulogin' \
	'-Dagetty-path=/sbin/agetty' \
	'-Dswapon-path=/sbin/swapon' \
	'-Dswapoff-path=/sbin/swapoff' \
	'-Dnologin-path=/sbin/nologin' \
	'-Dkmod-path=/usr/bin/kmod' \
	'-Dsplit-bin=true'; do
	grep -Fq -- "$path_flag" "$systemd_recipe" || {
		printf '%s\n' "systemd recipe lost split-layout helper pin: $path_flag" >&2
		exit 1
	}
done
# Feature-policy pins (audit 2026-10-09): gnutls/bzip2 are type=feature
# (auto) and must stay explicitly disabled so no future transitive -dev
# can flip them on by detection. utmp needs no pin (upstream forces it
# off under -Dlibc=musl); the recipe comment records that decision.
for feature_flag in \
	'-Dgnutls=disabled' \
	'-Dbzip2=disabled'; do
	grep -Fq -- "$feature_flag" "$systemd_recipe" || {
		printf '%s\n' "systemd recipe lost feature-policy pin: $feature_flag" >&2
		exit 1
	}
done
# r4 native PID1: the recipe must place a real /sbin/init (copy, never a
# symlink to the merged layout) and must remove upstream's merged-usr
# usr/sbin/init link. The fail-closed install assertions guard the rest.
for pid1_fragment in \
	'"$PKGDEST/sbin/init"' \
	'rm -f -- "$PKGDEST/usr/sbin/init"'; do
	grep -Fq -- "$pid1_fragment" "$systemd_recipe" || {
		printf '%s\n' "systemd recipe lost native-PID1 install step: $pid1_fragment" >&2
		exit 1
	}
done
# The default-grub init= line (0ece176) remains only as belt-and-braces:
# it rested on the bad assumption that the 261 /sbin/init symlink would
# survive upgrade, which a clean package transition disproves. r4 ships a
# real /sbin/init, so the kernel's ordinary search is the supported path -
# acceptance boots must omit init= to prove it. The line stays (removing
# it is baselayout scope) but nothing may depend on it.
grep -Fq 'init=/usr/lib/systemd/systemd' "$source_root/saphira-baselayout/files/default-grub" || {
	printf '%s\n' 'default-grub lost init= belt-and-braces (r4 /sbin/init is the supported path; test boots must omit init=)' >&2
	exit 1
}

# nginx /var/run contract (r11): a /usr/sbin service keeps runtime state
# under /var/run, never /run; /run and /var/run are separate real trees,
# neither a symlink. RuntimeDirectory= is unusable (systemd always
# creates it under /run), so the unit creates the dir with a privileged
# ExecStartPre before nginx -t runs. None of these may silently revert.
nginx_unit=$source_root/nginx/files/nginx.service
grep -Fq 'ExecStartPre=+/bin/install -d -o nginx -g nginx -m 0755 /var/run/nginx' "$nginx_unit" || {
	printf '%s\n' 'nginx.service lost privileged /var/run/nginx ExecStartPre' >&2
	exit 1
}
grep -Fq 'RuntimeDirectory=' "$nginx_unit" && {
	printf '%s\n' 'nginx.service must not use RuntimeDirectory= (wrong tree: always /run)' >&2
	exit 1
}
nginx_recipe=$source_root/nginx/recipe.sh
for pid_flag in \
	'--pid-path=/var/run/nginx/nginx.pid' \
	'--lock-path=/var/run/nginx/nginx.lock'; do
	grep -Fq -- "$pid_flag" "$nginx_recipe" || {
		printf '%s\n' "nginx recipe lost /var/run pid-path pin: $pid_flag" >&2
		exit 1
	}
done

# /etc/inittab belongs to OpenRC, not baselayout and not systemd: the
# OpenRC sysvinit table must never ship on systemd machines via the
# always-installed baselayout, and systemd must never own it. apk
# ownership then governs both switch directions with no hooks.
grep -Fq 'files/inittab' "$source_root/saphira-baselayout/recipe.sh" && {
	printf '%s\n' 'saphira-baselayout must not install etc/inittab (OpenRC-owned)' >&2
	exit 1
}
[ -e "$source_root/saphira-baselayout/files/inittab" ] && {
	printf '%s\n' 'saphira-baselayout/files/inittab must not exist (moved to openrc)' >&2
	exit 1
}
grep -Fq '"$RECIPE_DIR/files/inittab" "$PKGDEST/etc/inittab"' "$source_root/openrc/recipe.sh" || {
	printf '%s\n' 'openrc recipe lost etc/inittab install (OpenRC-owned sysvinit table)' >&2
	exit 1
}
[ -f "$source_root/openrc/files/inittab" ] || {
	printf '%s\n' 'openrc/files/inittab stock file missing' >&2
	exit 1
}

# openvswitch /var/run contract (r6): same root-/bin-vs-usr-/usr rule as
# nginx - the suite runs from /usr, so /var/run/openvswitch, root-owned.
# No RuntimeDirectory= (wrong tree). The fhs.d migration declaration
# ships (merge line: the fhs.d migration/reconciliation machinery
# survives, so the r4 fragment is carried again alongside the r5
# /var/run commitment).
ovs_unit=$source_root/openvswitch/files/openvswitch.service
grep -Fq 'ExecStartPre=+/bin/install -d -o root -g root -m 0755 /var/run/openvswitch' "$ovs_unit" || {
	printf '%s\n' 'openvswitch.service lost privileged /var/run/openvswitch ExecStartPre' >&2
	exit 1
}
grep -Fq 'RuntimeDirectory=' "$ovs_unit" && {
	printf '%s\n' 'openvswitch.service must not use RuntimeDirectory= (wrong tree: always /run)' >&2
	exit 1
}
ovs_recipe=$source_root/openvswitch/recipe.sh
grep -Fq -- '--with-rundir=/var/run/openvswitch' "$ovs_recipe" || {
	printf '%s\n' 'openvswitch recipe lost /var/run rundir pin' >&2
	exit 1
}
grep -Fq 'saphira/fhs.d/openvswitch' "$ovs_recipe" || {
	printf '%s\n' 'openvswitch recipe lost fhs.d migration declaration install' >&2
	exit 1
}
[ -f "$source_root/openvswitch/files/fhs.d/openvswitch" ] || {
	printf '%s\n' 'openvswitch/files/fhs.d/openvswitch fragment missing' >&2
	exit 1
}

# Regulatory freedom (article): every versioned kernel recipe must flip
# the cfg80211 gatekeeper Kconfig defaults, carry both symbols as
# explicit "is not set", and prove the final .config post-olddefconfig
# via the gate (the original defect was silent re-enabling at build).
for kver in 7.1.5 7.2.2 7.2.3 7.3-rc1; do
	k_recipe=$source_root/saphira-kernel-$kver/recipe.sh
	grep -Fq 'cfg80211-regdb-freedom.patch' "$k_recipe" || {
		printf '%s\n' "saphira-kernel-$kver lost regdb Kconfig patch" >&2
		exit 1
	}
	grep -Fq 'check_regdb_freedom' "$k_recipe" || {
		printf '%s\n' "saphira-kernel-$kver lost regdb-freedom gate call" >&2
		exit 1
	}
	grep -qxF '# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set' \
		"$source_root/saphira-kernel-$kver/files/config-$kver-akadata" || {
		printf '%s\n' "saphira-kernel-$kver config re-enabled signed-regdb" >&2
		exit 1
	}
	grep -qxF '# CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS is not set' \
		"$source_root/saphira-kernel-$kver/files/config-$kver-akadata" || {
		printf '%s\n' "saphira-kernel-$kver config re-enabled kernel regdb keys" >&2
		exit 1
	}
	grep -qxF 'CONFIG_DRM_FBDEV_EMULATION=y' \
		"$source_root/saphira-kernel-$kver/files/config-$kver-akadata" || {
		printf '%s\n' "saphira-kernel-$kver config lost KMS fbdev emulation (blind physical console)" >&2
		exit 1
	}
done

# FHS migration declarations (hotfix/var-packaging-bug-var-run-isnot-run):
# every files/fhs.d/* fragment must parse under makepkg's strict
# grammar, migrated exact paths must be unique across the whole tree
# (one package owns each path; parent/child pairs coexist), and the
# baselayout global fragment must pin the historical alias swap plus
# the /usr/var residue removal.
fhs_base=$source_root/saphira-baselayout/files/fhs.d/saphira-baselayout
[ -f "$fhs_base" ] || {
	printf '%s\n' 'baselayout global fhs.d fragment is missing' >&2
	exit 1
}
grep -Eq '^replace-symlink-dir /var/run \.\./run 0755 root root$' "$fhs_base" || {
	printf '%s\n' 'baselayout fragment must declare the /var/run historical swap' >&2
	exit 1
}
grep -Eq '^dir /var/run 0755 root root$' "$fhs_base" || {
	printf '%s\n' 'baselayout fragment must declare the real /var/run directory' >&2
	exit 1
}
grep -Eq '^replace-symlink-dir /var/lock \.\./run/lock 0755 root root$' "$fhs_base" || {
	printf '%s\n' 'baselayout fragment must declare the /var/lock historical swap' >&2
	exit 1
}
grep -Eq '^rmtree-or-fail /usr/var$' "$fhs_base" || {
	printf '%s\n' 'baselayout fragment must declare the /usr/var residue removal' >&2
	exit 1
}
"${SAPHIRA_PYTHON:-python3}" - "$source_root" <<'PY'
import importlib.machinery
import importlib.util
import sys
from pathlib import Path
source_root = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader(
    "makepkg_rules", str(source_root / "saphira-packager/files/makepkg"))
spec = importlib.util.spec_from_loader("makepkg_rules", loader)
mk = importlib.util.module_from_spec(spec)
loader.exec_module(mk)
seen: dict[str, str] = {}
errors: list[str] = []
for fragment in sorted(source_root.glob("*/files/fhs.d/*")):
    if fragment.name.endswith(".legacy"):
        errors.append(f"{fragment}: no legacy sidecars in fhs.d")
        continue
    try:
        decl = mk.parse_fhs_fragment(fragment)
    except Exception as exc:
        errors.append(f"{fragment}: {exc}")
        continue
    owner = fragment.parent.parent.parent.name
    for entry in decl["dirs"]:
        path = entry["path"]
        if path in seen and seen[path] != owner:
            errors.append(f"FHS path {path}: claimed by {seen[path]} and {owner}")
        seen.setdefault(path, owner)
    for entry in decl["replaces"]:
        path = entry["linkpath"]
        if path in seen and seen[path] != owner:
            errors.append(f"FHS path {path}: claimed by {seen[path]} and {owner}")
        seen.setdefault(path, owner)
    for entry in decl["removals"]:
        path = entry["path"]
        if path in seen and seen[path] != owner:
            errors.append(f"FHS path {path}: claimed by {seen[path]} and {owner}")
        seen.setdefault(path, owner)
if errors:
    for error in errors:
        print(f"fhs.d gate: {error}", file=sys.stderr)
    sys.exit(1)
PY

# saphira-permissions V1: every files/caps.d/* fragment must parse
# under makepkg's strict caps grammar, capped paths must be unique
# across the whole tree (one package owns each path - the
# same-payload-target rule plus the file gate enforce it at
# publish; this asserts the static tree), every caps target must
# ship in the owning recipe's payload (install line present), and
# the Python capability list must match the shell override
# helper's OVR_CAP_NAMES exactly (two canonical copies, one test).
"${SAPHIRA_PYTHON:-python3}" - "$source_root" <<'PY'
import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path
source_root = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader(
    "makepkg_rules", str(source_root / "saphira-packager/files/makepkg"))
spec = importlib.util.spec_from_loader("makepkg_rules", loader)
mk = importlib.util.module_from_spec(spec)
loader.exec_module(mk)
seen: dict[str, str] = {}
errors: list[str] = []
for fragment in sorted(source_root.glob("*/files/caps.d/*")):
    owner = fragment.parent.parent.parent.name
    try:
        decl = mk.parse_caps_fragment(fragment)
    except Exception as exc:
        errors.append(f"{fragment}: {exc}")
        continue
    for entry in decl["caps"]:
        path = entry["path"]
        if path in seen and seen[path] != owner:
            errors.append(f"caps path {path}: claimed by {seen[path]} and {owner}")
        seen.setdefault(path, owner)
# Every caps target must be installed by the owning recipe (a
# declaration for a file the recipe never ships fails the build;
# this pins the install lines statically).
for fragment in sorted(source_root.glob("*/files/caps.d/*")):
    owner = fragment.parent.parent.parent.name
    try:
        recipe = (source_root / owner / "recipe.sh").read_text(encoding="utf-8")
    except OSError:
        errors.append(f"{fragment}: owning recipe is missing")
        continue
    try:
        decl = mk.parse_caps_fragment(fragment)
    except Exception:
        continue
    for entry in decl["caps"]:
        if f"files/caps.d/{fragment.name}" not in recipe:
            errors.append(f"{owner}: caps.d/{fragment.name} is not installed by recipe.sh")
# Capability list parity: makepkg (Python) vs override helper (sh).
helper = (source_root / "saphira-baselayout/files/libexec/permissions-override.sh").read_text(encoding="utf-8")
match = re.search(r'^OVR_CAP_NAMES="([^"]*)"', helper, re.M)
if not match:
    errors.append("permissions-override.sh: OVR_CAP_NAMES is missing")
elif set(match.group(1).split()) != set(mk.SAPHIRA_CAP_NAMES):
    errors.append("capability lists differ: makepkg SAPHIRA_CAP_NAMES vs OVR_CAP_NAMES")
if errors:
    for error in errors:
        print(f"caps.d gate: {error}", file=sys.stderr)
    sys.exit(1)
PY

# V1 migration pins: breathgslb and alfred carry declarative caps.d
# fragments (alfred exercises all three fragment kinds at once);
# their build-time setcap lines are gone.
for migrated in breathgslb alfred; do
	fragment=$source_root/$migrated/files/caps.d/$migrated
	[ -f "$fragment" ] || {
		printf '%s\n' "$migrated caps.d fragment is missing" >&2
		exit 1
	}
	if grep -Eq '^[[:space:]]*setcap ' "$source_root/$migrated/recipe.sh"; then
		printf '%s\n' "$migrated still runs build-time setcap (migrate to caps.d)" >&2
		exit 1
	fi
done
grep -Eq '^cap /usr/sbin/breathgslb cap_net_bind_service\+ep$' \
	"$source_root/breathgslb/files/caps.d/breathgslb" || {
	printf '%s\n' 'breathgslb caps.d must declare cap_net_bind_service on /usr/sbin/breathgslb' >&2
	exit 1
}
grep -Eq '^cap /usr/sbin/alfred cap_net_admin,cap_net_raw\+ep$' \
	"$source_root/alfred/files/caps.d/alfred" || {
	printf '%s\n' 'alfred caps.d must declare cap_net_admin,cap_net_raw on /usr/sbin/alfred' >&2
	exit 1
}

printf '%s\n' 'recipe metadata rules tests: OK'

# Incident: proftpd compiled PR_RUN_DIR=/usr/var (bare --prefix without
# --localstatedir) and lynx installed to /usr/etc (bare --prefix without
# --sysconfdir) - autoconf silently derives both from the prefix. The
# configure-layout baseline for genuine Autoconf recipes is explicit
# --prefix, --sysconfdir and --localstatedir; recipes whose configure
# is custom (fio/talloc/lzip), waf-driven, cabal-driven, or otherwise
# outside GNU dir-flag semantics carry a documented layout-exception
# instead. Naive greps would flag those; this gate understands the
# distinction: a recipe invoking configure must either pass all three
# flags or document its exception.
"${SAPHIRA_PYTHON:-python3}" - "$source_root" <<'PY'
import re
import sys
from pathlib import Path
source_root = Path(sys.argv[1])
LINE_RE = re.compile(
    r"^(\s*)(?:[A-Za-z_]+=(?:\"[^\"]*\"|'[^']*'|\S+)\s+)*(\S+)(.*)$")


def is_configure_cmd(token):
    token = token.strip("\"'")
    base = token.rsplit("/", 1)[-1]
    return base in ("configure", "configure.sh")


errors: list[str] = []
for recipe in sorted(source_root.glob("*/recipe.sh")):
    text = recipe.read_text(encoding="utf-8")
    invoked = False
    for line in text.splitlines():
        m = LINE_RE.match(line)
        if m and is_configure_cmd(m.group(2)):
            invoked = True
            break
    if not invoked:
        continue
    has_all = ("--prefix=" in text and "--sysconfdir=" in text
               and "--localstatedir=" in text)
    exempt = "layout-exception:" in text
    if not has_all and not exempt:
        missing = [flag for flag in ("--prefix=", "--sysconfdir=",
                                     "--localstatedir=") if flag not in text]
        errors.append(f"{recipe.parent.name}/recipe.sh: configure layout "
                      f"baseline incomplete (missing {', '.join(missing)}); "
                      f"add the flags or document a layout-exception")
if errors:
    for error in errors:
        print(f"configure layout gate: {error}", file=sys.stderr)
    sys.exit(1)
PY

printf '%s\n' 'configure layout rules tests: OK'
