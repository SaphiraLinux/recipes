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

# lldpd owns its privilege-separation identity (_lldpd:124,
# convergent with nothing - it must be a fresh reservation).
lldpd_fragment=$source_root/lldpd/files/accounts.d/lldpd
[ -f "$lldpd_fragment" ] || {
	printf '%s\n' 'lldpd fragment is missing (_lldpd identity unowned)' >&2
	exit 1
}
grep -Eq '^user _lldpd 124 _lldpd /run/lldpd /sbin/nologin$' "$lldpd_fragment" || {
	printf '%s\n' 'lldpd fragment does not declare user _lldpd 124' >&2
	exit 1
}
grep -Eq '^group _lldpd 124$' "$lldpd_fragment" || {
	printf '%s\n' 'lldpd fragment does not declare group _lldpd 124' >&2
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

printf '%s\n' 'recipe metadata rules tests: OK'
