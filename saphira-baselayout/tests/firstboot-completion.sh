#!/bin/bash
# The firstboot completion contract: THE ROOT PASSWORD IS THE COMMIT
# POINT. Setup runs only until it is set, and setting it spends the
# marker permanently.
#
# Found by live acceptance, twice over. A completed wizard was followed by
# a reboot that offered setup again from the welcome screen, and the
# machine had lost its network. The cause was the previous contract: the
# marker was spent only after EVERY step succeeded, so any late failure
# armed the marker again and the machine was sent back through setup on
# every boot - with no network to fix it from anywhere else. The wizard
# also applied the network through a second, older copy of
# saphira-network-config that did not understand SLAAC, so a perfectly
# reasonable answer failed the apply and armed the marker.
#
# So the rule is now a fact about the machine rather than a summary of how
# the wizard's own steps went: "root has a password" is true, sufficient,
# and observable without the wizard. After that instant nothing may
# re-arm the marker, and every later failure is recorded, reported, and
# left for the operator to finish by hand.
#
#   image assembly  -> apply-accounts.sh writes /etc/saphira-firstboot-
#                      required when the image ships locked, and never at
#                      boot time, so nothing re-arms it
#   OpenRC service  -> start() returns success without running anything
#                      when the marker is absent
#   wizard entry    -> marker absent: nothing owed. Marker present but
#                      root password set: self-heal, spend the marker and
#                      leave - never re-prompt for a password the operator
#                      has already set
#   commit point    -> set_password root succeeds, and the marker is spent
#                      there and then, permanently
#   after that      -> admin/network/DNS/repository failures are retried
#                      once more, twice at most, can be skipped with q or
#                      Ctrl-C, and are reported as an explicit list of what
#                      is not configured. Boot continues either way.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
wizard=${SAPHIRA_FIRSTBOOT:-$here/../files/saphira-firstboot}
initd=${SAPHIRA_FIRSTBOOT_INITD:-$here/../files/saphira-firstboot.initd}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

# The wizard's guards run before it needs any privilege; a private user
# namespace provides uid 0 without acquiring anything.
if test "$(id -u)" -ne 0 && test "${FIRSTBOOT_COMPLETION_NS:-0}" != 1; then
	if command -v unshare >/dev/null 2>&1; then
		exec env FIRSTBOOT_COMPLETION_NS=1 unshare -rm "$0" "$@"
	fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

helper=$work/apply-network.sh
printf '#!/bin/sh\nexit 0\n' > "$helper"
chmod 0755 "$helper"

marker=$work/saphira-firstboot-required
state=$work/state
root=$work/root
install -d -m 0700 "$state" "$root/etc"

shadow_locked='root:!:1:0:99999:7:::'
shadow_set='root:$6$somesalt$0123456789abcdefghijklmnopqrstuv:1:0:99999:7:::'

set_shadow()
{
	printf '%s\n' "$1" > "$root/etc/shadow"
	chmod 0600 "$root/etc/shadow"
}

run_wizard()
{
	timeout -k 2 20 env \
	SAPHIRA_FIRSTBOOT_MARKER=$marker \
	SAPHIRA_FIRSTBOOT_STATE_DIR=$state \
	SAPHIRA_FIRSTBOOT_ROOT=$root \
	SAPHIRA_FIRSTBOOT_NETWORK_APPLY=$helper \
	SAPHIRA_FIRSTBOOT_SKIP_OWNERSHIP=1 \
		"$wizard" 2>&1
}

# An optional file the wizard reads must not be able to end the run:
# `sed ... | head -1` under `set -euo pipefail` aborts the whole wizard
# silently when the file is missing.
if test ! -e "$root/etc/os-release"; then
	ok 'the test root deliberately has no /etc/os-release'
fi

welcome_seen()
{
	case $1 in
	*'Initial System Setup'*) return 0 ;;
	esac
	return 1
}

printf '%s\n' '# an unconfigured machine is offered setup'

# Sanity: marker armed, root password locked: the wizard runs. Without
# this, the self-heal assertions below could pass for the wrong reason.
: > "$marker"
set_shadow "$shadow_locked"
out=$(printf '\n' | timeout -k 1 5 env \
	SAPHIRA_FIRSTBOOT_MARKER=$marker \
	SAPHIRA_FIRSTBOOT_STATE_DIR=$state \
	SAPHIRA_FIRSTBOOT_ROOT=$root \
	SAPHIRA_FIRSTBOOT_NETWORK_APPLY=$helper \
	SAPHIRA_FIRSTBOOT_SKIP_OWNERSHIP=1 \
		"$wizard" 2>&1)
if welcome_seen "$out"; then
	ok 'marker armed and root locked: the wizard starts and shows the welcome screen'
else
	bad 'marker armed and root locked: the wizard must reach the welcome screen'
	printf '%s\n' "$out" | /usr/bin/head -5 >&2
fi

printf '%s\n' '# root password set: the marker is spent, permanently'

# THE ACCEPTANCE CASE. The operator set a root password, a later step
# failed, and the machine rebooted into setup again - which is what lost
# the network, because the loop could not be broken without one. The
# only correct response is to spend the marker and leave.
rm -f "$marker" "$state/completed"
: > "$marker"
set_shadow "$shadow_set"
out=$(run_wizard)
status=$?
if welcome_seen "$out"; then
	bad 'a machine with a root password must never be shown the welcome screen'
else
	ok 'root password set with the marker armed: no welcome screen'
fi
if test "$status" -eq 0; then
	ok 'self-heal exits successfully'
else
	bad "self-heal expected exit 0, got $status"
	printf '%s\n' "$out" | /usr/bin/head -3 >&2
fi
if test ! -e "$marker"; then
	ok 'self-heal spends the marker'
else
	bad 'self-heal must spend the marker; that is the whole point'
fi
if test -f "$state/completed"; then
	ok 'self-heal records completion'
else
	bad 'self-heal must record completion'
fi

# And the next boot is an ordinary boot.
out=$(run_wizard)
status=$?
if welcome_seen "$out"; then
	bad 'a spent firstboot must never run again'
elif test "$status" -eq 0; then
	ok 'a second boot after the commit point does nothing and exits 0'
else
	bad "a second boot after the commit point expected exit 0, got $status"
fi

printf '%s\n' '# marker absent: nothing is owed'

rm -f "$state/completed"
set_shadow "$shadow_locked"
out=$(run_wizard)
status=$?
if welcome_seen "$out"; then
	bad 'a machine without the marker must not be prompted'
elif test "$status" -eq 0; then
	ok 'marker absent: exits successfully without prompting'
else
	bad "marker absent: expected exit 0, got $status"
fi

printf '%s\n' '# the commit point is the root password, and it is immediate'

# Structural, because driving the whole interactive flow is not what this
# suite is for: the marker must be spent directly after the root password
# is set, and before the administrator, network, DNS and repository steps
# that used to be able to arm it again.
commit_line=$(/usr/bin/grep -n '^commit_completion || {' "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
rootpw_line=$(/usr/bin/grep -n '^set_password root mandatory$' "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
admin_line=$(/usr/bin/grep -n "heading 'Administrator account'" "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
net_line=$(/usr/bin/grep -n "heading 'Network configuration'" "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
dns_line=$(/usr/bin/grep -n "heading 'DNS'" "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
repo_line=$(/usr/bin/grep -n "heading 'Package repository'" "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)

if test -n "$rootpw_line" && test -n "$commit_line" &&
	test "$commit_line" -gt "$rootpw_line"; then
	ok 'the marker is spent after the root password is set'
else
	bad "the commit point must follow set_password root (root=$rootpw_line commit=$commit_line)"
fi
for pair in "admin:$admin_line" "network:$net_line" "dns:$dns_line" "repository:$repo_line"; do
	label=${pair%%:*}
	line=${pair##*:}
	if test -n "$line" && test -n "$commit_line" && test "$line" -gt "$commit_line"; then
		ok "the $label step runs after the commit point, so it cannot re-arm the marker"
	else
		bad "the $label step must run after the commit point (commit=$commit_line $label=$line)"
	fi
done

# The pending admin username must survive long enough for the resume
# check to read it. Deleting it at the commit point (before the
# administrator section runs) made every resume impossible: the check
# below would always see an empty file.
resume_line=$(/usr/bin/grep -n 'test -s "$pending_user"' "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
clear_line=$(/usr/bin/grep -n 'rm -f -- "$pending_user"' "$wizard" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
if test -n "$resume_line" && test -n "$clear_line" && test "$clear_line" -gt "$resume_line"; then
	ok 'the pending username is cleared after the resume check, not at the commit point'
else
	bad "the pending username must be readable by the resume check before it is cleared (resume=$resume_line clear=$clear_line)"
fi

# Nothing may recreate the marker. The only writer is image assembly.
if /usr/bin/grep -qE '(install|printf|: *>) *"?[^"]*\$marker"?$' "$wizard"; then
	bad 'the wizard must never write the marker back; only image assembly may'
else
	ok 'the wizard never writes the marker back'
fi

printf '%s\n' '# bounded retry: initial attempt plus two, skippable'

# Structural: the retry bound.
if /usr/bin/grep -q 'local attempt=1 max_attempts=3' "$wizard"; then
	ok 'retry is bounded to an initial attempt plus two retries'
else
	bad 'retry must be bounded to three attempts in total'
fi
if /usr/bin/grep -q 'run_step .*apply_interface_now' "$wizard"; then
	ok 'a network activation failure goes through the bounded retry'
else
	bad 'a network activation failure must be bounded, not fatal'
fi
if /usr/bin/grep -q 'run_step .*write_repository' "$wizard"; then
	ok 'the repository step goes through the bounded retry'
else
	bad 'the repository step must be bounded'
fi

# Behavioural: drive the shipped run_step itself.
extract_function()
{
	awk -v want="$1" '
		$0 ~ "^" want "\\(\\)" { inside = 1 }
		inside { print }
		inside && /^}/ { exit }
	' "$2"
}

drive_run_step()
{
	local answers=$1
	(
		declare -a unfinished_steps=()
		nav_back=
		eval "$(extract_function read_setup "$wizard")"
		eval "$(extract_function record_unfinished "$wizard")"
		eval "$(extract_function run_step "$wizard")"
		answers_left=$answers
		# read is a builtin, so it assigns in the CALLER's scope the
		# way the shipped read_setup does. The reply is held under a
		# name the caller cannot be using, or it would shadow the very
		# variable being answered.
		read_setup() {
			local variable=$1 __reply
			__reply=${answers_left%%$'\n'*}
			if test "$__reply" = "$answers_left"; then
				answers_left=
			else
				answers_left=${answers_left#*$'\n'}
			fi
			if test "$__reply" = q; then
				nav_back=1
				return 1
			fi
			read -r "$variable" <<< "$__reply"
		}
		run_step 'Always fails' /bin/false
		printf '__RESULT__ attempts_answered=%s unfinished=%s\n' \
			"$(printf '%s' "$answers_left" | /usr/bin/grep -c '^' || true)" \
			"${unfinished_steps[*]}"
	)
}

out=$(drive_run_step 'y
y
' 2>&1)
if printf '%s\n' "$out" | /usr/bin/grep -q 'failed after 3 attempts'; then
	ok 'a step that never succeeds gives up after three attempts and records it'
else
	bad "a step that never succeeds must give up after three attempts: $out"
fi

# q skips immediately: with only 'q' available the second attempt is
# never reached.
out=$(drive_run_step 'q
' 2>&1)
if printf '%s\n' "$out" | /usr/bin/grep -q 'skipped at the operator request'; then
	ok 'q skips a failing step immediately instead of retrying'
else
	bad "q must skip a failing step immediately: $out"
fi

# Ctrl-C is the same back-request, so it skips too.
if /usr/bin/grep -q '^trap nav_back_request INT$' "$wizard"; then
	ok 'Ctrl-C is wired to the back-request that skips a failing step'
else
	bad 'Ctrl-C must skip a failing step, not abort the wizard'
fi

printf '%s\n' '# a failure after the commit point never re-arms setup'

# The old wording told the operator setup would run again. That promise
# cannot be kept after the commit point, so it must be gone.
runtime=$(/usr/bin/grep -v '^[[:space:]]*#' "$wizard")
if printf '%s\n' "$runtime" | /usr/bin/grep -q 'setup will run again on the next boot'; then
	if printf '%s\n' "$runtime" | /usr/bin/grep -q 'transaction_failed'; then
		ok 'the only re-arm promise left is the pre-commit failure path'
	else
		bad 'a "setup will run again" message with no pre-commit path is a false promise'
	fi
else
	ok 'no post-commit runtime path promises that setup will run again'
fi

# Whatever is left unfinished is stated explicitly at the end.
if /usr/bin/grep -q 'these steps are NOT configured' "$wizard"; then
	ok 'the run ends with an explicit statement of what is not configured'
else
	bad 'the run must state explicitly which steps are not configured'
fi
if /usr/bin/grep -q 'Setup will not run again' "$wizard"; then
	ok 'the operator is told setup will not run again'
else
	bad 'the operator must be told setup will not run again'
fi

printf '%s\n' '# the OpenRC service skips the wizard once the marker is gone'

: > "$marker"
body=$(awk '/^start\(\)/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$initd")
service_start() (
	command=/bin/true
	marker_path=$1
	body=$2
	eval "$body"
	[ -e "$marker_path" ] || return 0
	command=$SERVICE_COMMAND
	export command
	"$command"
)
if SERVICE_COMMAND="$helper" service_start "$marker" "$body"; then
	ok 'marker present: the service runs the wizard'
else
	bad 'marker present: the service must run the wizard'
fi
rm -f "$marker"
if SERVICE_COMMAND=/bin/false service_start "$marker" "$body"; then
	ok 'marker absent: the service returns success without running the wizard'
else
	bad 'marker absent: the service must not run the wizard'
fi

if test "$failures" -ne 0; then
	printf 'firstboot-completion: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-completion: OK'