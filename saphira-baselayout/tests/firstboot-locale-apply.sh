#!/bin/bash
# The wizard's locale apply path, end to end, against the tool that
# actually runs at boot.
#
# The mode the wizard offers the operator must be expressible by the
# helper the boot service executes. So this drives the shipped helper
# (which writes the files) with crafted states: every selection the
# wizard offers must validate and land where the running system reads
# it, and every malformed state must fail loudly rather than write a
# half-applied configuration.
#
# Nothing here re-implements either side: the keymap and zoneinfo
# trees are fakes under the test root (pointed at by environment, the
# same way the network suite points at fake sysfs), but every rule
# enforced is the shipped helper's own.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
helper=${SAPHIRA_APPLY_LOCALE:-$here/../files/libexec/apply-locale.sh}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

test -x "$helper" || { printf 'helper not executable: %s\n' "$helper" >&2; exit 1; }

# The helper requires uid 0; a private user namespace provides it without
# acquiring anything.
if test "$(id -u)" -ne 0 && test "${FIRSTBOOT_LOCALE_NS:-0}" != 1; then
	if command -v unshare >/dev/null 2>&1; then
		exec env FIRSTBOOT_LOCALE_NS=1 unshare -rm "$0" "$@"
	fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

root=$work/root
state=$root/var/lib/saphira-firstboot
install -d -m 0755 "$root/etc" "$root/etc/saphira" "$state"
chmod 0700 "$state"
printf 'active\n' > "$state/active"
chmod 0600 "$state/active"

# Fake keymap and zoneinfo trees: the helper resolves names against
# these instead of the live system trees (which the build host may not
# even have). Empty files are enough - validation checks presence,
# never content.
install -d -m 0755 "$root/usr/share/keymaps/i386/qwerty" \
	"$root/usr/share/zoneinfo/Europe" \
	"$root/usr/share/zoneinfo/America" \
	"$root/usr/share/zoneinfo/posix/Europe"
: > "$root/usr/share/keymaps/i386/qwerty/uk.map.gz"
: > "$root/usr/share/keymaps/i386/qwerty/us.map.gz"
: > "$root/usr/share/zoneinfo/Europe/London"
: > "$root/usr/share/zoneinfo/Europe/Paris"
: > "$root/usr/share/zoneinfo/America/New_York"
: > "$root/usr/share/zoneinfo/posix/Europe/London"
: > "$root/usr/share/zoneinfo/Fake.tab"

helper_env()
{
	env SAPHIRA_LOCALE_ROOT=$root \
	    SAPHIRA_FIRSTBOOT_STATE_DIR=$state \
	    SAPHIRA_LOCALE_SKIP_OWNERSHIP=1 \
	    "$@"
}

write_state()
{
	local name=$1
	{
		printf 'LANG=%s\n' "$2"
		printf 'KEYMAP=%s\n' "$3"
		printf 'TIMEZONE=%s\n' "$4"
		printf 'COUNTRY=%s\n' "$5"
		printf 'REGION=%s\n' "$6"
		printf 'CITY=%s\n' "$7"
		printf 'LATITUDE=%s\n' "$8"
		printf 'LONGITUDE=%s\n' "$9"
	} > "$state/$name.conf"
	chmod 0600 "$state/$name.conf"
	printf '%s\n' "$state/$name.conf"
}

# label LANG KEYMAP TIMEZONE COUNTRY REGION CITY LAT LONG expect
scenario()
{
	local label=$1
	local state_file
	state_file=$(write_state "$label" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9")
	shift 9
	local want=$1 out status
	out=$(helper_env "$helper" apply "$state_file" 2>&1)
	status=$?
	# The state file name is the label with spaces; the helper only
	# reads its content, so spaces are harmless here.
	if test "$want" = accept; then
		if test "$status" -ne 0; then
			bad "$label: the helper rejected it: $out"
			return
		fi
		ok "$label: the helper accepts it"
	else
		if test "$status" -eq 0; then
			bad "$label: the helper should have rejected it"
			return
		fi
		ok "$label: the helper rejects it"
	fi
}

printf '%s\n' '# the selections the wizard offers validate and land where the system reads them'

rm -rf "$root/etc/locale.conf" "$root/etc/vconsole.conf" "$root/etc/localtime" \
	"$root/etc/timezone" "$root/etc/saphira/location.conf"
state_file=$(write_state 'full' en_GB.UTF-8 uk Europe/London GB England Portsmouth 50.79685 -1.09117)
helper_env "$helper" apply "$state_file" >/dev/null
test "$(cat "$root/etc/locale.conf" 2>/dev/null)" = 'LANG=en_GB.UTF-8' &&
	ok 'locale.conf carries the selected language' ||
	bad "locale.conf wrong: $(cat "$root/etc/locale.conf" 2>/dev/null)"
test "$(cat "$root/etc/vconsole.conf" 2>/dev/null)" = 'KEYMAP=uk' &&
	ok 'vconsole.conf carries the selected keymap' ||
	bad "vconsole.conf wrong: $(cat "$root/etc/vconsole.conf" 2>/dev/null)"
test "$(readlink "$root/etc/localtime" 2>/dev/null)" = '/usr/share/zoneinfo/Europe/London' &&
	ok 'localtime links the selected zoneinfo' ||
	bad "localtime wrong: $(readlink "$root/etc/localtime" 2>/dev/null)"
test "$(cat "$root/etc/timezone" 2>/dev/null)" = 'Europe/London' &&
	ok 'timezone carries the bare zone name' ||
	bad "timezone wrong: $(cat "$root/etc/timezone" 2>/dev/null)"
grep -q '^COUNTRY=GB$' "$root/etc/saphira/location.conf" 2>/dev/null &&
grep -q '^CITY=Portsmouth$' "$root/etc/saphira/location.conf" 2>/dev/null &&
grep -q '^LATITUDE=50.79685$' "$root/etc/saphira/location.conf" 2>/dev/null &&
	ok 'location.conf carries the asserted location' ||
	bad "location.conf wrong: $(cat "$root/etc/saphira/location.conf" 2>/dev/null)"
if grep -q '^TIMEZONE=' "$root/etc/saphira/location.conf" 2>/dev/null; then
	bad 'location.conf must not duplicate the timezone (single source: /etc/localtime)'
else
	ok 'location.conf carries no duplicated timezone'
fi

printf '%s\n' '# no location answers means no location file, not an empty one'

rm -f "$root/etc/saphira/location.conf"
state_file=$(write_state 'noloc' en_GB.UTF-8 uk Europe/London '' '' '' '' '')
helper_env "$helper" apply "$state_file" >/dev/null
if test ! -e "$root/etc/saphira/location.conf"; then
	ok 'location.conf is absent when no location was given'
else
	bad 'location.conf must not exist when no location was given'
fi

printf '%s\n' '# malformed states fail loudly'

scenario 'keymap traversal' en_GB.UTF-8 ../evil Europe/London '' '' '' '' '' reject
scenario 'unknown keymap' en_GB.UTF-8 dvorak-nope Europe/London '' '' '' '' '' reject
scenario 'timezone traversal' en_GB.UTF-8 uk ../etc/shadow '' '' '' '' '' reject
scenario 'timezone is a directory' en_GB.UTF-8 uk Europe '' '' '' '' '' reject
scenario 'unknown timezone' en_GB.UTF-8 uk Mars/Olympus '' '' '' '' '' reject
scenario 'locale with shell metacharacters' 'en_GB.UTF-8; id' uk Europe/London '' '' '' '' '' reject
scenario 'locale with a space' 'en US' uk Europe/London '' '' '' '' '' reject
scenario 'empty timezone' en_GB.UTF-8 uk '' '' '' '' '' '' reject
scenario 'country too long' en_GB.UTF-8 uk Europe/London GBR '' '' '' '' reject
scenario 'country lowercase' en_GB.UTF-8 uk Europe/London gb '' '' '' '' reject
scenario 'latitude out of range' en_GB.UTF-8 uk Europe/London GB '' '' 91 '' reject
scenario 'latitude overflow guard' en_GB.UTF-8 uk Europe/London GB '' '' 99999999999999999999999 '' reject
scenario 'latitude not a number' en_GB.UTF-8 uk Europe/London GB '' '' '50.8x' '' reject
scenario 'longitude out of range' en_GB.UTF-8 uk Europe/London GB '' '' '' 181 reject
scenario 'location without country' en_GB.UTF-8 uk Europe/London '' England Portsmouth '' '' reject

printf '%s\n' '# the state file itself is strict'

printf 'LANG=en_GB.UTF-8\nLANG=uk\n' > "$state/dupe.conf"
chmod 0600 "$state/dupe.conf"
if helper_env "$helper" validate "$state/dupe.conf" >/dev/null 2>&1; then
	bad 'a duplicated state field must be refused'
else
	ok 'a duplicated state field is refused'
fi
printf 'LANG=en_GB.UTF-8\nFROBNICATE=yes\n' > "$state/unknown.conf"
chmod 0600 "$state/unknown.conf"
if helper_env "$helper" validate "$state/unknown.conf" >/dev/null 2>&1; then
	bad 'an unknown state field must be refused'
else
	ok 'an unknown state field is refused'
fi
printf 'this is not a state file\n' > "$state/garbage.conf"
chmod 0600 "$state/garbage.conf"
if helper_env "$helper" validate "$state/garbage.conf" >/dev/null 2>&1; then
	bad 'a garbage state file must be refused'
else
	ok 'a garbage state file is refused'
fi

printf '%s\n' '# apply-answers: the standalone path validates identically and writes directly'

rm -rf "$root/etc/locale.conf" "$root/etc/vconsole.conf" "$root/etc/localtime" \
	"$root/etc/timezone" "$root/etc/saphira/location.conf"
out=$(helper_env "$helper" apply-answers en_GB.UTF-8 us America/New_York US '' 'New York' '' '' 2>&1)
if test $? -ne 0; then
	bad "apply-answers rejected a valid invocation: $out"
elif test "$(cat "$root/etc/locale.conf")" = 'LANG=en_GB.UTF-8' &&
	test "$(readlink "$root/etc/localtime")" = '/usr/share/zoneinfo/America/New_York'; then
	ok 'apply-answers writes the files without a wizard transaction'
else
	bad 'apply-answers did not write the expected files'
fi
out=$(helper_env "$helper" apply-answers en_GB.UTF-8 us Mars/Olympus '' '' '' '' '' 2>&1)
if test $? -eq 0; then
	bad 'apply-answers must reject an invalid timezone'
else
	ok 'apply-answers rejects an invalid timezone'
fi
out=$(helper_env "$helper" apply-answers en_GB.UTF-8 uk 2>&1)
if test $? -eq 0; then
	bad 'apply-answers must fail on the wrong argument count'
else
	ok 'apply-answers fails closed on the wrong argument count'
fi

printf '%s\n' '# listers expose exactly the answer vocabulary validation accepts'

if helper_env "$helper" list-keymaps | grep -qx 'uk' &&
	helper_env "$helper" list-keymaps | grep -qx 'us'; then
	ok 'list-keymaps exposes the fake tree keymaps'
else
	bad 'list-keymaps missed the fake tree keymaps'
fi
if helper_env "$helper" list-timezones | grep -qx 'Europe/London' &&
	helper_env "$helper" list-timezones | grep -qx 'America/New_York'; then
	ok 'list-timezones exposes the fake tree zones'
else
	bad 'list-timezones missed the fake tree zones'
fi
if helper_env "$helper" list-timezones | grep -x 'posix/.*' >/dev/null; then
	bad 'list-timezones must not offer duplicate posix/ views'
else
	ok 'list-timezones hides duplicate posix/ views'
fi
if helper_env "$helper" list-timezones | grep -x '.*\.tab' >/dev/null; then
	bad 'list-timezones must not offer tables as zones'
else
	ok 'list-timezones hides tables'
fi

printf '%s\n' '# live keymap load refuses every unsafe invocation'

out=$(helper_env "$helper" load-keymap-live uk 2>&1)
if test $? -eq 0; then
	bad 'load-keymap-live must refuse a staged root'
else
	ok 'load-keymap-live refuses a staged root'
fi
out=$(env SAPHIRA_LOCALE_ROOT= SAPHIRA_LOCALE_SKIP_OWNERSHIP=1 PATH="$work/empty-path" "$helper" load-keymap-live uk 2>&1)
if test $? -eq 0; then
	bad 'load-keymap-live must fail without loadkeys'
else
	ok 'load-keymap-live fails closed without loadkeys'
fi

printf '%s\n' '# the post-commit guard: completed plus a live transaction applies'

printf 'completed\n' > "$state/completed"
chmod 0600 "$state/completed"
rm -f "$root/etc/locale.conf"
state_file=$(write_state 'postcommit' en_GB.UTF-8 uk Europe/London '' '' '' '' '')
out=$(helper_env "$helper" apply "$state_file" 2>&1)
if test $? -ne 0; then
	bad "the helper must apply with completed present and a live transaction: $out"
elif test -f "$root/etc/locale.conf"; then
	ok 'post-commit apply with a live transaction writes the files'
else
	bad 'post-commit apply succeeded but wrote nothing'
fi

printf '%s\n' '# a stale completed state with no live transaction is still refused'

rm -f "$state/active"
rm -f "$root/etc/locale.conf"
state_file=$(write_state 'stale' en_GB.UTF-8 uk Europe/London '' '' '' '' '')
out=$(helper_env "$helper" apply "$state_file" 2>&1)
if test $? -eq 0; then
	bad 'the helper must refuse a completed state with no live transaction'
else
	ok 'a stale completed state with no live transaction is refused'
fi

if test "$failures" -ne 0; then
	printf 'firstboot-locale-apply: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-locale-apply: OK'
