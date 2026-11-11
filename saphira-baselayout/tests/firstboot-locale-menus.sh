#!/bin/bash
# Firstboot's locale flow, driven as the shipped code.
#
# The functions under test are extracted mechanically from the installed
# saphira-firstboot at run time, so this can never drift from what the
# image actually runs: there is no second copy of the logic here.
#
# The order is the one the wizard implements:
#
#   locale (default en_GB.UTF-8) -> keymap (default uk) ->
#   timezone (default Europe/London) -> location (opt-in, default no),
#   each with q - and Ctrl-C, wired to the same back-request - stepping
#   back within the block.
#
# And the property the network flow already proved necessary: a wrong
# choice must be recoverable, and a defaulted answer must validate
# through the real helper, never through a stub.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)

# The static validation is performed by the real locale helper, and
# that helper requires uid 0. Rather than stub its rules - which would
# test this harness instead of the shipped code - re-exec inside a
# private user namespace, where uid 0 is ours alone.
if test "$(id -u)" -ne 0 && test "${FIRSTBOOT_LOCALE_MENUS_NS:-0}" != 1; then
	if command -v unshare >/dev/null 2>&1; then
		exec env FIRSTBOOT_LOCALE_MENUS_NS=1 unshare -rm "$0" "$@"
	fi
fi

wizard=${SAPHIRA_FIRSTBOOT:-$here/../files/saphira-firstboot}
helper=${SAPHIRA_APPLY_LOCALE:-$here/../files/libexec/apply-locale.sh}
failures=0

ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

test -r "$wizard" || { printf 'wizard not readable: %s\n' "$wizard" >&2; exit 1; }
test -x "$helper" || { printf 'helper not executable: %s\n' "$helper" >&2; exit 1; }

extract_function() {
	awk -v want="$1" '
		$0 ~ "^" want "\\(\\)" { inside = 1 }
		inside { print }
		inside && /^}/ { exit }
	' "$wizard"
}

for fn in read_setup choose_locale choose_keymap choose_timezone choose_location write_locale_state; do
	extract_function "$fn" >/dev/null || bad "$fn not found in $wizard"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Fake keymap and zoneinfo trees, exactly as in firstboot-locale-apply:
# the helper resolves names against these.
install -d -m 0755 "$work/keymaps/i386/qwerty" \
	"$work/zoneinfo/Europe" "$work/zoneinfo/America"
: > "$work/keymaps/i386/qwerty/uk.map.gz"
: > "$work/keymaps/i386/qwerty/us.map.gz"
: > "$work/keymaps/i386/qwerty/de.map.gz"
: > "$work/zoneinfo/Europe/London"
: > "$work/zoneinfo/Europe/Paris"
: > "$work/zoneinfo/America/New_York"

# Drive one scenario: the answer queue, then the functions to call.
# read_setup is the harness's own queue reader, modelling exactly what
# the shipped read_setup decides (q is back).
drive() {
	local answers=$1
	shift
	(
		LOCALE_LANG=en_GB.UTF-8 LOCALE_KEYMAP=uk LOCALE_TIMEZONE=Europe/London
		LOCALE_COUNTRY= LOCALE_REGION= LOCALE_CITY=
		LOCALE_LATITUDE= LOCALE_LONGITUDE=
		locale_apply=$helper
		locale_state=$work/locale.conf
		SAPHIRA_LOCALE_KEYMAP_DIR=$work/keymaps
		SAPHIRA_LOCALE_ZONEINFO_DIR=$work/zoneinfo
		export SAPHIRA_LOCALE_KEYMAP_DIR SAPHIRA_LOCALE_ZONEINFO_DIR
		eval "$(extract_function read_setup)"
		eval "$(extract_function choose_locale)"
		eval "$(extract_function choose_keymap)"
		eval "$(extract_function choose_timezone)"
		eval "$(extract_function choose_location)"
		eval "$(extract_function write_locale_state)"

		read_setup() {
			local variable=$1 reply
			if test -z "$answers_left"; then
				printf '%s\n' "$EOF_MARKER"
				exit 99
			fi
			reply=${answers_left%%$'\n'*}
			if test "$reply" = "$answers_left"; then
				answers_left=
			else
				answers_left=${answers_left#*$'\n'}
			fi
			# q is back, exactly as the shipped read_setup decides it.
			# NOTE: the scratch variable must NOT be named `answer`:
			# caller functions use that name for their own locals, and
			# printf -v obeys dynamic scope, so a stub-local `answer`
			# would swallow the value instead of setting the caller's.
			if test "$reply" = q; then
				nav_back=1
				return 1
			fi
			printf -v "$variable" '%s' "$reply"
		}

		answers_left=$answers
		EOF_MARKER='__would-block__'
		local fn status=0
		for fn in "$@"; do
			"$fn" || { status=1; break; }
		done
		printf '__RESULT__ LANG=%s KEYMAP=%s TIMEZONE=%s COUNTRY=%s REGION=%s CITY=%s LAT=%s LONG=%s\n' \
			"$LOCALE_LANG" "$LOCALE_KEYMAP" "$LOCALE_TIMEZONE" \
			"$LOCALE_COUNTRY" "$LOCALE_REGION" "$LOCALE_CITY" \
			"$LOCALE_LATITUDE" "$LOCALE_LONGITUDE"
		return $status
	)
}

run() {
	label=$1 answers=$2
	shift 2
	out=$(drive "$answers" "$@" 2>&1)
	status=$?
	case $out in
	*__would-block__*)
		bad "$label: the flow wanted more input than the scenario gave"
		return 1
		;;
	esac
	return $status
}

printf '%s\n' '# empty answers accept the proposed defaults, location stays unrecorded'

if run 'defaults' $'\n\n\nn\n' choose_locale choose_keymap choose_timezone choose_location; then
	case $out in
	*__RESULT__*LANG=en_GB.UTF-8*KEYMAP=uk*TIMEZONE=Europe/London*COUNTRY=\ *REGION=\ *CITY=\ *)
		ok 'defaults accepted: en_GB.UTF-8, uk, Europe/London, no location' ;;
	*) bad "defaults produced wrong values: $out" ;;
	esac
fi

printf '%s\n' '# explicit answers validate through the real helper and stick'

if run 'custom' $'de\nus\nAmerica/New_York\ny\nDE\nBrandenburg\nBerlin\n52.52\n13.40\n' \
		choose_locale choose_keymap choose_timezone choose_location; then
	case $out in
	*__RESULT__*LANG=de*KEYMAP=us*TIMEZONE=America/New_York*COUNTRY=DE*REGION=Brandenburg*CITY=Berlin*LAT=52.52*LONG=13.40*)
		ok 'custom answers validate and stick' ;;
	*) bad "custom answers produced wrong values: $out" ;;
	esac
fi

printf '%s\n' '# an invalid answer re-prompts instead of sticking'

if run 'invalid-keymap' $'xx-nope\nuk\n' choose_keymap; then
	case $out in
	*__RESULT__*KEYMAP=uk*) ok 'an unknown keymap re-prompts and the valid one sticks' ;;
	*) bad "invalid keymap handling wrong: $out" ;;
	esac
fi

if run 'invalid-timezone' $'Mars/Olympus\nEurope/Paris\n' choose_timezone; then
	case $out in
	*__RESULT__*TIMEZONE=Europe/Paris*) ok 'an unknown timezone re-prompts and the valid one sticks' ;;
	*) bad "invalid timezone handling wrong: $out" ;;
	esac
fi

if run 'invalid-latitude' $'y\nGB\nEngland\nPortsmouth\n91\n50.79\n-1.09\n' choose_location; then
	case $out in
	*__RESULT__*LAT=50.79*LONG=-1.09*) ok 'an out-of-range latitude re-prompts and the valid one sticks' ;;
	*) bad "invalid latitude handling wrong: $out" ;;
	esac
fi

printf '%s\n' '# blank latitude/longitude skips the coordinate, not the location'

if run 'blank-coords' $'y\nGB\nEngland\nPortsmouth\n\n\n' choose_location; then
	case $out in
	*__RESULT__*COUNTRY=GB*REGION=England*CITY=Portsmouth*LAT=\ LONG=*)
		ok 'blank coordinates record the place without coordinates' ;;
	*) bad "blank coordinates produced wrong values: $out" ;;
	esac
fi

printf '%s\n' '# q steps back: the value is untouched and no further input is consumed'

if run 'back' $'q\n' choose_keymap; then
	bad 'q at a menu must report back (non-zero), not success'
else
	case $out in
	*KEYMAP=uk*__would-block__*)
		bad 'q must not consume further input' ;;
	*KEYMAP=uk*)
		ok 'q leaves the value untouched and consumes exactly one answer' ;;
	*) bad "q handling wrong: $out" ;;
	esac
fi

printf '%s\n' '# the staged state file carries exactly the chosen answers'

if run 'state-file' $'\n\n\nn\n' choose_locale choose_keymap choose_timezone choose_location; then
	rm -f "$work/locale.conf"
	(
		LOCALE_LANG=en_GB.UTF-8 LOCALE_KEYMAP=uk LOCALE_TIMEZONE=Europe/London
		LOCALE_COUNTRY= LOCALE_REGION= LOCALE_CITY=
		LOCALE_LATITUDE= LOCALE_LONGITUDE=
		locale_state=$work/locale.conf
		eval "$(extract_function write_locale_state)"
		write_locale_state
	)
	if grep -qx 'LANG=en_GB.UTF-8' "$work/locale.conf" 2>/dev/null &&
		grep -qx 'KEYMAP=uk' "$work/locale.conf" 2>/dev/null &&
		grep -qx 'TIMEZONE=Europe/London' "$work/locale.conf" 2>/dev/null; then
		ok 'write_locale_state stages the chosen answers'
	else
		bad "staged state wrong: $(cat "$work/locale.conf" 2>/dev/null)"
	fi
fi

if test "$failures" -ne 0; then
	printf 'firstboot-locale-menus: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-locale-menus: OK'
