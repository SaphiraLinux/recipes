#!/bin/sh

# Non-usrmerged filesystem policy: static assertions that no shipped
# service definition, init script or payload path assumes a usr-merged
# tree. No build required.
#
# Policy encoded (see RECIPE_RULES.md "Non-usrmerged filesystem policy"):
# - /bin, /sbin, /usr/bin, /usr/sbin are distinct trees BY DESIGN;
#   /lib is separate from /usr/lib; /lib64 and /usr/lib64 are forbidden.
# - A shipped unit/script must reference an executable by the path its
#   OWNING RECIPE actually installs it to.
# - Never create a usrmerge symlink (/bin -> /usr/bin and friends).
#
# Two incidents locked in here, both of which reached a shipped payload
# and could only be caught at boot:
#
#   coreutils is --bindir=/bin, so install/mkdir/rm/cat/cp/mv/ln/kill
#   live in /bin and /usr/bin/install does not exist. Ten shipped .service
#   files called /usr/bin/install or /usr/bin/mkdir in ExecStartPre= and
#   would have died 203/EXEC. Not one .initd had the bug, which is exactly
#   why the OpenRC boot matrix stayed green and the systemd matrix went
#   unexercised.
#
#   hostapd installs $PKGDEST/usr/bin/hostapd and asserts it, but shipped
#   hostapd.service pointed ExecStart at /usr/sbin/hostapd while its own
#   hostapd@.service and hostapd.initd used /usr/bin/hostapd. Self-
#   inconsistent inside one package.
#
# usage: non-usrmerge.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

fail()
{
	printf '%s\n' "non-usrmerge: $*" >&2
	exit 1
}

# Violations are appended to a file rather than counted in a variable.
# Almost every scan below runs inside a `| while read` pipeline, i.e. a
# subshell, so an increment there would be lost and the summary count
# would under-report. The file is the single source of truth.
violations=$(mktemp "${SAPHIRA_TMPDIR:-/build/tmp}/non-usrmerge-violations.XXXXXX")
trap 'rm -f -- "$violations" "${violations}.idx"' EXIT HUP INT TERM
: > "$violations"

report()
{
	printf '%s\n' "non-usrmerge: $*" >&2
	printf '%s\n' "$*" >> "$violations"
}

# --- 1. Absolute path -> owning recipe index ---------------------------
#
# Derived from the tree rather than hardcoded, so a legitimate hit is
# allowed automatically and a moved binary is caught the day it moves.
# Only EXECUTABLE payload paths are indexed: a recipe that installs
# /usr/bin/foo is the authority that /usr/bin/foo is the right spelling.

# dir prefix (relative to $PKGDEST) -> newline-separated absolute paths
installs_exe()
{
	# $PKGDEST/... paths this recipe installs that are executable in a
	# running system: the usual bin/sbin/libexec prefixes, plus the
	# package-private /var/qmail-style prefixes a daemon may own.
	awk '
		/\$PKGDEST/ {
			line = $0
			sub(/^.*\$PKGDEST\//, "", line)
			sub(/^"\$PKGDEST\//, "", line)
			sub(/["].*$/, "", line)
			sub(/'"'"'.*$/, "", line)
			sub(/[[:space:]].*$/, "", line)
			if (line == "") next
			if (line !~ /^(usr\/)?(s?bin)\//) next
			if (line ~ /\.example$|\.conf$|\.sample$/) next
			printf "/%s\n", line
		}
	' "$1" | sed -e 's/[$][{][A-Za-z_][A-Za-z0-9_]*[}]//g' | sort -u
}

# The set of directory prefixes a coreutils-style tool may legitimately
# live under. A reference must be under one of these, or be a path some
# recipe actually installs.
usr_managed_prefixes='/usr/bin/ /usr/sbin/ /bin/ /sbin/'

# Everything a shipped definition may point an executable at.
definitions_list()
{
	for pattern in \
		"$source_root"/*/files/*.service \
		"$source_root"/*/files/*.initd \
		"$source_root"/*/files/*.timer \
		"$source_root"/*/files/*.path \
		"$source_root"/*/files/*.mount \
		"$source_root"/*/files/openrc-boot/*
	do
		[ -f "$pattern" ] && printf '%s\n' "$pattern"
	done
}

# Collect the tree-wide set of installed executable paths once.
installed_index="${violations}.idx"
: > "$installed_index"
for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	installs_exe "$recipe" >> "$installed_index"
done
sort -u -o "$installed_index" "$installed_index"

# Sanctioned root-initialisation links and interpreter shims.
# /bin/sh -> bash is owned by the bash package (relative link, target and
# link in the same package); it stays resolvable here through the installed
# index derived from recipes. /usr/bin/env -> /bin/env is still created by
# saphira-bootstrap in a target root and by buildpkg in a clean build root
# and owned by no package. /sbin/openrc-run is openrc's own interpreter.
sanctioned_paths='
/usr/bin/env
/sbin/openrc-run
/usr/bin/openrc-run
'

is_known_executable()
{
	case "$sanctioned_paths" in
		*"
$1
"*) return 0 ;;
	esac
	grep -Fxq -- "$1" "$installed_index"
}

# --- 2. Check 1: no /usr/bin/<coreutils> in any shipped definition ----
#
# Not a substring denylist. The tool set is fixed and each entry is a
# real coreutils program that Saphira installs into /bin.

coreutils_tools=' install mkdir rmdir rm cp mv ln cat kill chmod chown
chgrp ln touch mkdir mknod mkfifo sleep true false test expr id ls
readlink realpath basename dirname head tail sort uniq cut tr wc date
rmdir shred install mv stat sync tee tty stty uname seq timeout yes env
printf echo who whoami df du find grep sed awk xargs cp ln nohup nice '

for def in $(definitions_list); do
	pkg=$(basename "$(dirname "$(dirname "$def")")")
	rel=${def#"$source_root/$pkg/files/"}
	# Pull the first token of every Exec*= / command= / supervisor= line
	# plus every bare absolute path appearing in the file. `+' and `-'
	# prefixes are systemd's permission markers; strip them.
	sed -n -e 's/^[[:space:]]*\(Exec[A-Za-z]*\|command\|command_args\|supervisor\)=[[:space:]]*//p' \
		-e 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=[[:space:]]*//p' \
		"$def" 2>/dev/null |
		tr ' \t' '\n\n' |
		sed -e 's/^[+-]//' |
		grep '^/' |
		sort -u > "${installed_index}.cands" 2>/dev/null || :
	for cand in $(cat "${installed_index}.cands" 2>/dev/null); do
		case $cand in
			/usr/bin/*)
				tool=${cand#/usr/bin/}
				case $tool in
					''|*/*) continue ;;
				esac
				# A single word drawn from the coreutils set that no
				# recipe installs under /usr/bin. Saphira's
				# coreutils is --bindir=/bin, so this cannot work.
				case " $coreutils_tools " in
					*" $tool "*)
						if ! grep -Fxq -- "/usr/bin/$tool" "$installed_index"; then
							report "$pkg: $rel references /usr/bin/$tool but no recipe installs it there (coreutils is --bindir=/bin; use /bin/$tool)"
						fi
						;;
				esac
				;;
		esac
	done
	rm -f -- "${installed_index}.cands"
done

# --- 3. Check 2: no unit contradicts its own package's install path ----
#
# A full static index of "which path does every daemon land on" is not
# derivable: most recipes reach the payload through `make install
# DESTDIR=$PKGDEST` plus a `--sbindir=` flag, so the literal path never
# appears in the recipe. Guessing produced nothing but false positives
# (/usr/sbin/named, /bin/kill and /usr/sbin/nft are all correct).
#
# What IS provable, and is the actual defect class, is a package whose own
# recipe names one directory for a binary while its own shipped unit names
# another. hostapd: recipe installs $PKGDEST/usr/bin/hostapd and asserts
# `test -x` on it, while hostapd.service says /usr/sbin/hostapd, and the
# same package's hostapd@.service and hostapd.initd say /usr/bin/hostapd.
#
# So: for every absolute path a definition points at, if the SAME package
# installs a binary of the same basename under a different prefix, the
# definition is wrong by construction.

# Directories a recipe may install an executable into, keyed by basename.
pkg_installs()
{
	# $1 = recipe path, $2 = package name
	awk -v pkg="$2" '
		/\$PKGDEST/ {
			line = $0
			sub(/^.*\$PKGDEST\//, "", line)
			sub(/^"\$PKGDEST\//, "", line)
			sub(/["].*$/, "", line)
			sub(/'"'"'.*$/, "", line)
			sub(/[[:space:]].*$/, "", line)
			if (line == "") next
			if (line !~ /^(usr\/)?(s?bin|libexec)\//) next
			if (line ~ /\.(example|conf|sample|so|la|a)$/) next
			n = split(line, parts, "/")
			printf "%s %s\n", parts[n], "/" line
		}
	' "$1" | sed -e 's/[$][{][A-Za-z_][A-Za-z0-9_]*[}]//g' | sort -u
}

for def in $(definitions_list); do
	pkg=$(basename "$(dirname "$(dirname "$def")")")
	rel=${def#"$source_root/$pkg/files/"}
	recipe=$source_root/$pkg/recipe.sh
	[ -f "$recipe" ] || continue
	pkg_manifest=$(pkg_installs "$recipe" "$pkg")
	[ -n "$pkg_manifest" ] || continue

	# Collect the basename -> path pairs this definition claims.
	sed -n -e 's/^[[:space:]]*Exec[A-Za-z]*=[[:space:]]*//p' \
		-e 's/^[[:space:]]*command=[[:space:]]*//p' \
		-e 's/^[[:space:]]*PIDFile=[[:space:]]*//p' \
		"$def" 2>/dev/null |
		tr ' \t' '\n\n' |
		sed -e 's/^[+-]//' -e 's/^["'\'']//' -e 's/["'\'']$//' |
		grep '^/' | sort -u > "${installed_index}.cands" 2>/dev/null || :
	[ -s "${installed_index}.cands" ] || continue

	while IFS= read -r cand; do
		[ -n "$cand" ] || continue
		case $cand in
			/usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*) ;;
			*) continue ;;
		esac
		# A glob or an interpolation is not a literal path claim.
		case $cand in
			*'*'*|*'$'*|*'?'*|*'{'*|*'%'*) continue ;;
		esac
		case $cand in */) continue ;; esac
		base=${cand##*/}
		# Where does this package's own recipe put that basename?
		own=$(printf '%s\n' "$pkg_manifest" | awk -v b="$base" '$1 == b { print $2 }' | head -n 1)
		[ -n "$own" ] || continue
		[ "$own" = "$cand" ] && continue
		report "$pkg: $rel points at $cand but this recipe installs $base at $own"
	done < "${installed_index}.cands"
	rm -f -- "${installed_index}.cands"
done

# --- 4. Check 3: no usrmerge symlink creation -------------------------
#
# A usrmerge link is specifically one WRITTEN INTO a distinct tree while
# POINTING INTO its usr counterpart. Matching merely on "usr/bin appears
# on the line" is wrong: `ln -s libbz2.so.1.0.8 $PKGDEST/usr/lib/...` is the
# ordinary, correct case (a SONAME link inside the same tree), as are
# `ln -s python3 $PKGDEST/usr/bin/python` and the sanctioned
# `/usr/bin/env -> /bin/env` shim.
#
# The offender was in the installer, not a recipe:
#   saphira-baselayout/files/libexec/apply-accounts.sh
#     ln -sfn ../usr/bin/passwd "$ROOTFS/bin/passwd"
# which plants a link in the distinct /bin tree pointing into /usr, so a
# /usr-less emergency boot has a dangling /bin/passwd and the merged-world
# mental model is normalised in the one script that builds the root.

usrmerge_link()
{
	# $1 = file, $2 = label for the message
	awk -v label="$2" '
		# Only lines that create a link.
		$0 !~ /ln[ \t]+(-[a-zA-Z]+[ \t]+)*-?[a-z]*n?[a-z]*f?[a-z]*[ \t]/ { next }
		# The link must be written INTO bin/, sbin/ or lib/ (the
		# distinct trees). /usr/... destinations are ordinary.
		{
			into_distinct = 0
			if (match($0, /(\$PKGDEST|\$ROOTFS|\$target|\$\{?[A-Za-z_]+\}?)(\/)?\/(usr\/)?(bin|sbin|lib)\//)) {
				split($0, a, "/")
				# find the component sequence right after the root var
				rest = $0
				sub(/^.*(\$PKGDEST|\$ROOTFS|\$target)\//, "", rest)
				split(rest, b, "/")
				if (b[1] == "bin" || b[1] == "sbin" || b[1] == "lib") into_distinct = 1
			}
			if (!into_distinct) next
		}
		# ...and the link must POINT INTO the usr counterpart.
		$0 !~ /(\.\.\/)*usr\/(bin|sbin|lib)/ { next }
		# The sanctioned root-init shim, created by saphira-bootstrap
		# and asserted by buildpkg.
		$0 ~ /\/usr\/bin\/env/ { next }
		$0 ~ /\.\.\/\.\.\/bin\/env/ { next }
		# A comment is not a link.
		$0 ~ /^[ \t]*#/ { next }
		{ printf "%s: line %d: %s\n", label, FNR, $0 }
	' "$1"
}

for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=$(basename "$(dirname "$recipe")")
	usrmerge_link "$recipe" "$pkg recipe.sh" | while IFS= read -r line; do
		report "usrmerge link: $line"
	done
done

# Shipped payload scripts (installers, init scripts, helpers) install
# into a target root, not into $PKGDEST, so match their own root vars.
# Recursive: the offenders live in nested payload subtrees
# (files/libexec/apply-accounts.sh), not only files/<script>.
find "$source_root" -path "$source_root/.git" -prune -o \
	-type f -path "*/files/*" -print | sort | while IFS= read -r payload; do
	case $payload in
		*/lib64/*|*.patch|*.diff) continue ;;
	esac
	pkg=${payload#"$source_root/"}; pkg=${pkg%%/*}
	rel=${payload#"$source_root/$pkg/files/"}
	usrmerge_link "$payload" "$pkg files/$rel" | while IFS= read -r line; do
		report "usrmerge link: $line"
	done
done

# --- 5. Check 4: no /lib64 or /usr/lib64, no ldconfig -----------------

for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=$(basename "$(dirname "$recipe")")
	# A create, not a reference: mkdir/install/ln into lib64.
	if grep -nE '(PKGDEST|install[[:space:]]+-D|mkdir)[[:space:]].*/usr?/lib64' "$recipe" 2>/dev/null |
		grep -vE '^\s*#|rm -|rm -f' >/dev/null 2>&1; then
		grep -nE '(PKGDEST|install[[:space:]]+-D|mkdir)[[:space:]].*/usr?/lib64' "$recipe" |
			grep -vE 'rm -' |
			while IFS= read -r line; do
				case $line in
					*'#'*) continue ;;
				esac
				report "$pkg: recipe.sh creates a lib64 path: $line"
			done
	fi
done

# Saphira has no ldconfig: musl's search path is compiled in. An
# ldconfig invocation would paper over a misplaced library.
for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=$(basename "$(dirname "$recipe")")
	grep -nE '(^|[;&|[:space:]])ldconfig([[:space:]]|$)' "$recipe" 2>/dev/null |
		while IFS= read -r line; do
			case $line in
				*'#'*|*'--disable-ldconfig'*) continue ;;
			esac
			report "$pkg: recipe.sh runs ldconfig; Saphira has no ldconfig (fix library placement): $line"
		done
done

# --- 6. Check 5: no /var/run <-> /run alias creation -----------------

find "$source_root" -path "$source_root/.git" -prune -o \
	-type f -path "*/files/*" -print | sort | while IFS= read -r payload; do
	case $payload in
		*/lib64/*|*.patch|*.diff) continue ;;
	esac
	pkg=${payload#"$source_root/"}; pkg=${pkg%%/*}
	rel=${payload#"$source_root/$pkg/files/"}
	grep -nE 'ln[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-?[^[:space:]]*[[:space:]]+[^[:space:]]*(var/run|/run)' "$payload" 2>/dev/null |
		while IFS= read -r line; do
			# A symlink INTO one of the two is fine (a service
			# making its own runtime dir). A symlink FROM one to
			# the other is the alias the split-run patch removed.
			case $line in
				*'var/run'*'/'*'/run'*|*'/'*'var/run'*) continue ;;
			esac
			report "$pkg: files/$rel aliases /var/run and /run; Saphira keeps them distinct: $line"
		done
done

failures=$(wc -l < "$violations")
if [ "$failures" -gt 0 ]; then
	printf '%s\n' "non-usrmerge: $failures violation(s); see RECIPE_RULES.md 'Non-usrmerged filesystem policy'" >&2
	exit 1
fi

printf '%s\n' 'non-usrmerge: OK (executable paths, usrmerge symlinks, lib64, ldconfig, /var/run aliases)'
