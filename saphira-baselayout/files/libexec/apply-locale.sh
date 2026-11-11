#!/bin/bash
# Locale, console keymap, timezone and physical-location writer for
# saphira-firstboot (and for later standalone reconfiguration, which
# firstboot itself can never do: it runs exactly once).
#
# Non-usrmerged PATH (same reason as apply-network.sh): invoked by the
# firstboot wizard, which itself runs under minimal boot PATH.
#
# Split of responsibility, mirroring the network side: this helper
# validates answers and writes the files; the wizard owns the menus,
# the summary and the apply decision. Nothing here prompts.

set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

test "$(id -u)" -eq 0 || {
	printf 'apply-locale: must be run as root\n' >&2
	exit 1
}

LOCALE_ROOT=${SAPHIRA_LOCALE_ROOT:-}
KEYMAP_DIR=${SAPHIRA_LOCALE_KEYMAP_DIR:-$LOCALE_ROOT/usr/share/keymaps}
ZONEINFO_DIR=${SAPHIRA_LOCALE_ZONEINFO_DIR:-$LOCALE_ROOT/usr/share/zoneinfo}

fail()
{
	printf 'apply-locale: ERROR: %s\n' "$*" >&2
	exit 1
}

# Keymap names are basenames loadkeys itself resolves (uk, de-latin1,
# dvorak...): no slashes ever, so a keymap answer can never escape the
# keymap tree no matter what the caller passes.
valid_keymap_name()
{
	local name=$1
	[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
}

keymap_file()
{
	# What loadkeys would load for this name: the first regular file
	# found walking the keymap tree. bash globstar, no find dependency
	# (minimal roots may not ship find).
	local name=$1 candidate
	shopt -s globstar nullglob
	for candidate in "$KEYMAP_DIR"/**/"$name".map \
			 "$KEYMAP_DIR"/**/"$name".map.gz \
			 "$KEYMAP_DIR"/**/"$name".map.bz2 \
			 "$KEYMAP_DIR"/**/"$name".map.xz; do
		if test -f "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

valid_keymap()
{
	local name=$1
	valid_keymap_name "$name" || return 1
	keymap_file "$name" >/dev/null
}

list_keymaps()
{
	# Basenames without extension, unique and sorted: the exact answer
	# vocabulary valid_keymap accepts.
	local file base
	shopt -s globstar nullglob
	for file in "$KEYMAP_DIR"/**/*.map \
		     "$KEYMAP_DIR"/**/*.map.gz \
		     "$KEYMAP_DIR"/**/*.map.bz2 \
		     "$KEYMAP_DIR"/**/*.map.xz; do
		test -f "$file" || continue
		base=${file##*/}
		case $base in
		*.map.gz) base=${base%.map.gz} ;;
		*.map.bz2) base=${base%.map.bz2} ;;
		*.map.xz) base=${base%.map.xz} ;;
		*.map) base=${base%.map} ;;
		esac
		printf '%s\n' "$base"
	done | sort -u
}

# Timezone names are relative zoneinfo paths (Europe/London). A name
# with a .. component or a leading slash is rejected before it ever
# reaches the filesystem, so validation can never read outside the
# zoneinfo tree.
valid_timezone_name()
{
	local name=$1
	[[ $name =~ ^[A-Za-z0-9_+-][A-Za-z0-9_+./-]*$ ]] || return 1
	[[ $name != *..* ]] || return 1
}

valid_timezone()
{
	local name=$1
	valid_timezone_name "$name" || return 1
	test -f "$ZONEINFO_DIR/$name" || return 1
}

list_timezones()
{
	# Regular files only (regions are directories, not answers),
	# relative to the zoneinfo root, sorted. *.tab are tables, not
	# zones; posix/ and right/ are duplicate views of the default
	# files, so they are excluded rather than offered twice.
	local file
	shopt -s globstar nullglob
	for file in "$ZONEINFO_DIR"/**/*; do
		test -f "$file" || continue
		file=${file#"$ZONEINFO_DIR"/}
		case $file in
		*.tab|posix/*|right/*|leapseconds*|tzdata.zi) continue ;;
		esac
		printf '%s\n' "$file"
	done | sort
}

# musl honours C.UTF-8 natively; anything else is best-effort fallback
# (proven: the locale step documents this rather than promising
# glibc-style locale data). The shape check keeps garbage out of
# /etc/locale.conf without pretending to verify linguistic data.
valid_locale()
{
	[[ ${1:-} =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_-]+)?(@[A-Za-z0-9_-]+)?$ ]]
}

valid_country()
{
	[[ ${1:-} =~ ^[A-Z]{2}$ ]]
}

valid_place()
{
	# Free-text region/city: printable, bounded, no padding. The state
	# file is KEY=value lines, so a value is one line by construction.
	local value=$1
	[[ -n $value ]] || return 1
	((${#value} <= 64)) || return 1
	[[ $value != *[^[:print:]]* ]] || return 1
	[[ $value != ' '* && $value != *' ' ]] || return 1
}

valid_coord()
{
	# Pure-bash range check: no awk dependency on minimal roots.
	# Integer part longer than three digits cannot be a latitude or
	# longitude, and is rejected before arithmetic (which under
	# set -e must never see an overflowing value).
	local value=$1 hi=$2 int frac
	[[ $value =~ ^(-)?([0-9]+)(\.([0-9]+))?$ ]] || return 1
	int=${BASH_REMATCH[2]}
	frac=${BASH_REMATCH[4]:-}
	((${#int} <= 3)) || return 1
	((10#$int <= hi)) || return 1
	if ((10#$int == hi)); then
		[[ -z $frac || $frac =~ ^0*$ ]] || return 1
	fi
}

valid_latitude()
{
	valid_coord "${1:-}" 90
}

valid_longitude()
{
	valid_coord "${1:-}" 180
}

load_state()
{
	local state=$1 line key value
	declare -A seen_fields=()
	test -f "$state" || fail "locale state is absent: $state"
	unset LANG KEYMAP TIMEZONE COUNTRY REGION CITY LATITUDE LONGITUDE
	while IFS= read -r line || test -n "$line"; do
		test -z "$line" && continue
		key=${line%%=*}
		value=${line#*=}
		[[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || fail "invalid state field"
		test "$line" != "$key" || fail "state field has no value: $key"
		case $key in
		LANG|KEYMAP|TIMEZONE|COUNTRY|REGION|CITY|LATITUDE|LONGITUDE) ;;
		*) fail "unknown state field: $key" ;;
		esac
		test -z "${seen_fields[$key]:-}" || fail "duplicate state field: $key"
		seen_fields[$key]=1
		printf -v "$key" '%s' "$value"
	done < "$state"
	LANG=${LANG:-}; KEYMAP=${KEYMAP:-}; TIMEZONE=${TIMEZONE:-}
	COUNTRY=${COUNTRY:-}; REGION=${REGION:-}; CITY=${CITY:-}
	LATITUDE=${LATITUDE:-}; LONGITUDE=${LONGITUDE:-}
}

validate_state()
{
	valid_locale "$LANG" || fail "invalid LANG: $LANG"
	valid_keymap "$KEYMAP" || fail "invalid KEYMAP: $KEYMAP"
	valid_timezone "$TIMEZONE" || fail "invalid TIMEZONE: $TIMEZONE"
	if test -n "$COUNTRY$REGION$CITY$LATITUDE$LONGITUDE"; then
		test -n "$COUNTRY" || fail "COUNTRY is required when any location field is set"
		valid_country "$COUNTRY" || fail "invalid COUNTRY (ISO alpha-2): $COUNTRY"
		if test -n "$REGION"; then
			valid_place "$REGION" || fail "invalid REGION: $REGION"
		fi
		if test -n "$CITY"; then
			valid_place "$CITY" || fail "invalid CITY: $CITY"
		fi
		if test -n "$LATITUDE"; then
			valid_latitude "$LATITUDE" || fail "invalid LATITUDE: $LATITUDE"
		fi
		if test -n "$LONGITUDE"; then
			valid_longitude "$LONGITUDE" || fail "invalid LONGITUDE: $LONGITUDE"
		fi
	fi
}

write_file()
{
	local dest=$1 content=$2 temporary
	temporary=$(mktemp "$(dirname -- "$dest")/.locale.XXXXXX")
	printf '%s' "$content" > "$temporary"
	chmod 0644 "$temporary"
	test "${SAPHIRA_LOCALE_SKIP_OWNERSHIP:-0}" = 1 || chown 0:0 "$temporary"
	mv -f "$temporary" "$dest"
	rm -f "$temporary"
}

check_locale_transaction()
{
	local state=$1 state_dir=$2 active completed
	active=$state_dir/active
	completed=$state_dir/completed
	# Same transaction discipline as the network apply: a completed
	# state with no live transaction is stale and must be refused, so
	# a stale marker can never drive a write.
	if test -e "$completed" && test ! -f "$active"; then
		fail 'firstboot has already completed'
	fi
	test -d "$state_dir" || fail 'firstboot state directory is absent'
	if test "${SAPHIRA_LOCALE_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$state_dir")" = 700 ||
			fail 'firstboot state directory is not protected'
	else
		test "$(stat -c %u:%a "$state_dir")" = '0:700' ||
			fail 'firstboot state directory is not protected'
	fi
	test -f "$active" || fail 'no active firstboot transaction'
	if test "${SAPHIRA_LOCALE_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$active")" = 600 ||
			fail 'firstboot transaction is not protected'
	else
		test "$(stat -c %u:%a "$active")" = '0:600' ||
			fail 'firstboot transaction is not protected'
	fi
	test "$(dirname -- "$state")" -ef "$state_dir" ||
		fail 'locale state is outside the firstboot transaction directory'
	if test "${SAPHIRA_LOCALE_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$state")" = 600 ||
			fail 'locale state is not protected'
	else
		test "$(stat -c %u:%a "$state")" = '0:600' ||
			fail 'locale state is not protected'
	fi
}

write_locale_files()
{
	# The write half, shared by the wizard path (apply STATE, guarded
	# above) and the standalone path (apply-answers, unguarded by
	# construction). Validation always runs first in both callers.
	install -d -m 0755 "$LOCALE_ROOT/etc" "$LOCALE_ROOT/etc/saphira"
	write_file "$LOCALE_ROOT/etc/locale.conf" "LANG=$LANG
"
	write_file "$LOCALE_ROOT/etc/vconsole.conf" "KEYMAP=$KEYMAP
"
	# /etc/localtime is a symlink at the packaged zoneinfo path (musl
	# and systemd both resolve it); /etc/timezone carries the bare name
	# for readers that parse text rather than following the link.
	write_file "$LOCALE_ROOT/etc/timezone" "$TIMEZONE
"
	rm -f "$LOCALE_ROOT/etc/.localtime.new"
	ln -sfn "/usr/share/zoneinfo/$TIMEZONE" "$LOCALE_ROOT/etc/.localtime.new"
	mv -f "$LOCALE_ROOT/etc/.localtime.new" "$LOCALE_ROOT/etc/localtime"
	# Location is metadata, not configuration: timezone authority stays
	# with /etc/localtime, so TIMEZONE is deliberately not duplicated
	# here (two sources for one fact always diverge). No location
	# answers at all means no file, not an empty one.
	if test -n "$COUNTRY$REGION$CITY$LATITUDE$LONGITUDE"; then
		location_tmp=$(mktemp "$LOCALE_ROOT/etc/saphira/.location.XXXXXX")
		{
			printf 'COUNTRY=%s\n' "$COUNTRY"
			test -n "$REGION" && printf 'REGION=%s\n' "$REGION"
			test -n "$CITY" && printf 'CITY=%s\n' "$CITY"
			test -n "$LATITUDE" && printf 'LATITUDE=%s\n' "$LATITUDE"
			test -n "$LONGITUDE" && printf 'LONGITUDE=%s\n' "$LONGITUDE"
		} > "$location_tmp"
		chmod 0644 "$location_tmp"
		test "${SAPHIRA_LOCALE_SKIP_OWNERSHIP:-0}" = 1 ||
			chown 0:0 "$location_tmp"
		mv -f "$location_tmp" "$LOCALE_ROOT/etc/saphira/location.conf"
		rm -f "$location_tmp"
	fi
}

apply_locale()
{
	check_locale_transaction "$1" "$2"
	write_locale_files
}

apply_answers()
{
	# Standalone post-boot reconfiguration (firstboot never re-runs):
	# positional answers on the command line, empty string for any
	# optional location field left unset. No transaction checks by
	# construction - this path never runs inside a wizard transaction -
	# but validation is identical to the wizard path.
	test $# -eq 8 || fail 'usage: apply-locale.sh apply-answers LANG KEYMAP TIMEZONE [COUNTRY] [REGION] [CITY] [LATITUDE] [LONGITUDE]'
	local state
	state=$(mktemp)
	chmod 0600 "$state"
	{
		printf 'LANG=%s\n' "$1"
		printf 'KEYMAP=%s\n' "$2"
		printf 'TIMEZONE=%s\n' "$3"
		printf 'COUNTRY=%s\n' "$4"
		printf 'REGION=%s\n' "$5"
		printf 'CITY=%s\n' "$6"
		printf 'LATITUDE=%s\n' "$7"
		printf 'LONGITUDE=%s\n' "$8"
	} > "$state"
	load_state "$state"
	validate_state
	write_locale_files
	rm -f "$state"
}

load_keymap_live()
{
	# Immediate console effect for the running system (the wizard calls
	# this after writing vconsole.conf, so the rest of the session uses
	# the chosen layout). Live only: a chrooted or staged root has no
	# console to change, and loadkeys outside the live system is
	# meaningless rather than merely untestable.
	local name=$1
	valid_keymap "$name" || fail "invalid KEYMAP: $name"
	test -z "$LOCALE_ROOT" || test "$LOCALE_ROOT" = / ||
		fail 'live keymap load requires the live root'
	command -v loadkeys >/dev/null 2>&1 ||
		fail 'loadkeys is not available (kbd is not installed)'
	loadkeys -q "$name" || fail "loadkeys could not activate: $name"
}

state_dir_default()
{
	printf '%s\n' "${SAPHIRA_FIRSTBOOT_STATE_DIR:-/var/lib/saphira-firstboot}"
}

case ${1:-} in
	validate) test $# -eq 2 || fail 'usage: apply-locale.sh validate STATE'; load_state "$2"; validate_state ;;
	apply) test $# -eq 2 || fail 'usage: apply-locale.sh apply STATE'; load_state "$2"; validate_state; apply_locale "$2" "$(state_dir_default)" ;;
	apply-answers) shift; apply_answers "$@" ;;
	validate-locale) test $# -eq 2 && valid_locale "$2" || fail "invalid LANG: ${2:-}" ;;
	validate-keymap) test $# -eq 2 && valid_keymap "$2" || fail "invalid KEYMAP: ${2:-}" ;;
	validate-timezone) test $# -eq 2 && valid_timezone "$2" || fail "invalid TIMEZONE: ${2:-}" ;;
	validate-country) test $# -eq 2 && valid_country "$2" || fail "invalid COUNTRY: ${2:-}" ;;
	validate-place) test $# -eq 2 && valid_place "$2" || fail "invalid place name: ${2:-}" ;;
	validate-latitude) test $# -eq 2 && valid_latitude "$2" || fail "invalid LATITUDE: ${2:-}" ;;
	validate-longitude) test $# -eq 2 && valid_longitude "$2" || fail "invalid LONGITUDE: ${2:-}" ;;
	list-keymaps) test $# -eq 1 || fail 'usage: apply-locale.sh list-keymaps'; list_keymaps ;;
	list-timezones) test $# -eq 1 || fail 'usage: apply-locale.sh list-timezones'; list_timezones ;;
	load-keymap-live) test $# -eq 2 || fail 'usage: apply-locale.sh load-keymap-live KEYMAP'; load_keymap_live "$2" ;;
	*) fail 'usage: apply-locale.sh {validate|apply|apply-answers|validate-locale|validate-keymap|validate-timezone|validate-country|validate-place|validate-latitude|validate-longitude|list-keymaps|list-timezones|load-keymap-live} ...' ;;
esac
