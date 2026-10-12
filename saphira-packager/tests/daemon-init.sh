#!/bin/sh

# Dual init coverage: every package that installs a long-running daemon
# must ship BOTH /etc/init.d/<svc> and /usr/lib/systemd/system/<unit>.
# No build required.
#
# Policy encoded (see RECIPE_RULES.md "Dual init system policy"):
# - daemon-ness is decided by what a recipe INSTALLS, never by package
#   name. A name-based test cannot tell lldpd the daemon from clamdscan the
#   scanner, and "server-ish" is not "daemon".
# - utilities, libraries, clients and cluster helpers are exempt;
# - nothing is auto-enabled, nothing is auto-started.
#
# Detection, in order of authority:
#
#   1. the recipe installs a literal $PKGDEST/etc/init.d/... path -> openrc
#   2. the recipe installs a literal $PKGDEST/usr/lib/systemd/system/... path
#      -> systemd
#   3. the recipe points an upstream build system's unit-dir flag at
#      /usr/lib/systemd/system -> systemd (dbus: meson
#      -Dsystemd_system_unitdir). A flag pointed at a SUPPRESSION path
#      (/no/systemd, --without-systemd, -Dsystemd=disabled) is the opposite
#      of coverage and is recorded as a suppression, not as a unit.
#   4. a `daemon` entry in files/daemon-inventory.map, for daemons that
#      install no service file at all today.
#
# This gate exists because the coverage was 24/45 and nothing checked it.
# saphira-build's own audit computes has_openrc and has_systemd
# independently and both stages are only ever "pass" or "na", never "fail",
# so a one-sided or absent service definition PASSED. That is a reporter,
# not a gate, and it is one `and` away from being the enforcement the
# policy requires.
#
# usage: daemon-init.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
map_file=$source_root/saphira-packager/files/daemon-inventory.map

fail()
{
	printf '%s\n' "daemon-init: $*" >&2
	exit 1
}

violations=$(mktemp "${SAPHIRA_TMPDIR:-/build/tmp}/daemon-init-violations.XXXXXX")
trap 'rm -f -- "$violations" "$violations.rows"' EXIT HUP INT TERM
: > "$violations"
: > "$violations.rows"

report()
{
	printf '%s\n' "daemon-init: $*" >&2
	printf '%s\n' "$*" >> "$violations"
}

[ -f "$map_file" ] || fail "daemon inventory map is missing: $map_file"

# --- 1. What does each recipe install? ---------------------------------

# Emit "<pkg> <openrc|count> <systemd|count> <suppressed>" per recipe.
#
# `rm` lines are excluded: mariadb has `rm -f "$PKGDEST/etc/init.d/mysql"`,
# which is a DELETION of a path another package owns, not a service this
# package provides. Counting it would invent a false OpenRC side.
survey_recipe()
{
	pkg=$1
	recipe=$2
	openrc=0
	systemd=0
	suppressed=no
	while IFS= read -r line; do
		case $line in
			''|'#'*) continue ;;
		esac
		# A deletion is not an install.
		case $line in
			*rm\ *|*'\$PKGDEST'/etc/*'rm'*) continue ;;
		esac
		case $line in
			*'PKGDEST/etc/init.d/'*) openrc=$((openrc + 1)) ;;
			*'PKGDEST/usr/lib/systemd/system/'*) systemd=$((systemd + 1)) ;;
		esac
	done < "$recipe"

	# Upstream build-system unit dirs. A suppression is the opposite of
	# coverage and must never be counted as a unit.
	if grep -Eq 'systemd[_-]system[_-]unitdir[[:space:]]*=[[:space:]]*/usr/lib/systemd/system|with-systemdunitdir[[:space:]]*=[[:space:]]*/usr/lib/systemd/system|--with-systemdsystemdir=/usr/lib/systemd/system' "$recipe" 2>/dev/null; then
		systemd=$((systemd + 1))
	fi
	if grep -Eq 'systemd[_-]system[_-]unitdir[[:space:]]*=[[:space:]]*/no|--without-systemd|-Dsystemd=disabled|--with-systemdsystemdir=/no' "$recipe" 2>/dev/null; then
		suppressed=yes
	fi

	printf '%s %s %s %s\n' "$pkg" "$openrc" "$systemd" "$suppressed"
}

for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	survey_recipe "$(basename "$(dirname "$recipe")")" "$recipe" >> "$violations.rows"
done

# --- 2. Parse the inventory map ----------------------------------------

map_kind()
{
	# $1 = package, $2 = daemon|exempt|(absent)
	awk -v pkg="$1" '
		{
			line = $0
			sub(/#.*$/, "", line)
			gsub(/^[ \t]+|[ \t]+$/, "", line)
			if (line == "") next
			n = split(line, f, /[ \t]+/)
			if (f[1] != pkg) next
			if (n < 2) { print "malformed"; exit }
			print f[2]
			exit
		}
	' "$map_file"
}

# The reason is the TRAILING COMMENT, per the map format
#   <pkg> exempt # reason
# so it must be read from the comment side of the line, not from the
# token side. Reading the token side reported "no reason" for both
# exempt entries that plainly have one.
map_reason()
{
	awk -v pkg="$1" '
		{
			hash = index($0, "#")
			body = (hash ? substr($0, 1, hash - 1) : $0)
			comment = (hash ? substr($0, hash + 1) : "")
			gsub(/^[ \t]+|[ \t]+$/, "", body)
			gsub(/^[ \t]+|[ \t]+$/, "", comment)
			if (body == "") next
			n = split(body, f, /[ \t]+/)
			if (f[1] != pkg) next
			print comment
			exit
		}
	' "$map_file"
}

# --- 3. Enforce --------------------------------------------------------

detected_pkgs=0
declared_pkgs=0
exempt=0

while read -r pkg openrc systemd suppressed; do
	[ -n "$pkg" ] || continue
	kind=$(map_kind "$pkg")
	case $kind in
		malformed) fail "malformed inventory entry for $pkg" ;;
	esac

	has_openrc=0
	has_systemd=0
	[ "$openrc" -gt 0 ] && has_openrc=1
	[ "$systemd" -gt 0 ] && has_systemd=1

	# An init system cannot ship a unit for itself.
	if [ "$pkg" = openrc ] || [ "$pkg" = systemd ]; then
		continue
	fi

	# Detected as a service package by its own install lines.
	if [ "$has_openrc" -eq 1 ] || [ "$has_systemd" -eq 1 ]; then
		detected_pkgs=$((detected_pkgs + 1))
		if [ "$has_openrc" -eq 1 ] && [ "$has_systemd" -eq 1 ]; then
			# Compliant. A stale map entry should be dropped.
			if [ "$kind" = daemon ]; then
				report "$pkg: map says 'daemon' but the recipe now installs both formats; drop the stale map entry"
			declared_pkgs=$((declared_pkgs + 1))
			fi
			continue
		fi
		:
		if [ "$kind" = exempt ]; then
			# A deliberate, reviewed absence. Allowed, but only
			# when the package genuinely ships one side.
			exempt=$((exempt + 1))
			continue
		fi
		if [ "$has_systemd" -eq 1 ]; then
			report "$pkg ships only a systemd unit ($systemd) and no /etc/init.d service; dual-init policy requires both"
		else
			report "$pkg ships only an OpenRC service ($openrc) and no systemd unit; dual-init policy requires both"
			[ "$suppressed" = yes ] && \
				report "$pkg additionally configures its build to SUPPRESS the unit (--without-systemd / -Dsystemd=disabled / --with-systemdsystemdir=/no), so the unit does not exist upstream either; remove the suppression rather than working around it"
		fi
		# A one-sided package needs a map entry so the absence is
		# explicit rather than invisible.
		if [ "$kind" != daemon ] && [ "$kind" != exempt ]; then
			report "$pkg: add a 'daemon' or 'exempt <reason>' entry to saphira-packager/files/daemon-inventory.map so this state is declared, not accidental"
		fi
		continue
	fi

	# Installs no service file at all. Only the map can say whether that
	# is a real gap or a reviewed absence.
	case $kind in
		daemon)
			declared_pkgs=$((declared_pkgs + 1))
			report "$pkg is a declared daemon but ships NO service definition in either format; dual-init policy requires /etc/init.d/<svc> and /usr/lib/systemd/system/<unit>"
			;;
		exempt)
			exempt=$((exempt + 1))
			reason=$(map_reason "$pkg")
			[ -n "$reason" ] || report "exempt entry for $pkg has no reason"
			;;
		'')
			# Not a service package by detection and not declared.
			# That is the correct, common case: libraries, clients,
			# utilities. Nothing to do.
			;;
	esac
done < "$violations.rows"

# --- 4. The map itself must be well formed ----------------------------

seen=""
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	stripped=${line%%#*}
	case $stripped in
		''|' '*) continue ;;
		*[[:space:]]*) ;;
		*) continue ;;
	esac
	# shellcheck disable=SC2086
	set -- $stripped
	[ "$#" -ge 2 ] || {
		report "map line $lineno: malformed entry (need <pkg> daemon|exempt [reason]): $line"
		continue
	}
	pkg=$1
	kind=$2
	case $kind in
		daemon) ;;
		exempt)
			# The reason is the trailing comment, so test the
			# comment side of the line, not the token count.
			reason=$(map_reason "$pkg")
			[ -n "$reason" ] || \
				report "map line $lineno: exempt entry for $pkg needs a reason (a '# reason' comment)"
			;;
		*) report "map line $lineno: unknown kind '$kind' for $pkg" ;;
	esac
	[ -f "$source_root/$pkg/recipe.sh" ] || \
		report "map line $lineno: $pkg has no recipe; a stale entry makes the gate lie"
	case $seen in
		*" $pkg "*) report "map line $lineno: duplicate entry for $pkg" ;;
		*) seen="$seen $pkg" ;;
	esac
done < "$map_file"

count=$(wc -l < "$violations")
if [ "$count" -gt 0 ]; then
	printf '%s\n' "daemon-init: $count violation(s); $detected_pkgs package(s) detected as services from their install lines, $declared_pkgs declared daemon(s) shipping neither format, $exempt reviewed exemption(s); see RECIPE_RULES.md 'Dual init system policy'" >&2
	exit 1
fi

printf '%s\n' "daemon-init: OK ($detected_pkgs detected service package(s) all ship both formats, $declared_pkgs declared daemon(s) covered, $exempt reviewed exemption(s))"
