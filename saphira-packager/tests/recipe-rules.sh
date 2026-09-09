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
[ -f "$source_root/gd/files/gd-2.3.3.tar.xz" ] || {
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

printf '%s\n' 'recipe metadata rules tests: OK'
