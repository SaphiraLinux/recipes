#!/bin/sh
# saphira-bootstrap target acceptance: the same mount-aware rule as
# saphira-install. The assembler calls bootstrap with the target
# already mounted (including a separate /boot for --boot-size roots
# and every zfs root), so a naive emptiness check dies here even
# though the install tool already accepted the same target.
# (Proven live: the install got past saphira-install and died in
# saph vissa-bootstrap on the mounted /boot.)
#
# Everything here runs unprivileged in scratch directories, with a
# stub apk and a fake root check. Mounts are simulated the same way
# as in install-target-emptiness.sh: a fake `stat` on PATH reports a
# different device for everything at or under the fake mountpoint,
# which is exactly what a real mount looks like to the check.

set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=${SAPHIRA_BOOTSTRAP:-$here/../files/saphira-bootstrap}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/profiles"
printf 'sometestpackage\n' > "$work/profiles/testprofile"
cat > "$work/bin/apk-stub" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$work/bin/id-stub" <<'EOF'
#!/bin/sh
echo 0
EOF
chmod +x "$work/bin/apk-stub" "$work/bin/id-stub"

run_boot()
{
	# run_boot <target> [extra...]: bootstrap with stubs; the tool
	# cannot finish a real install here (no rootfs is assembled by a
	# true apk), so "the gate passed" means the failure, if any, is
	# something other than the target-emptiness refusal.
	# PATH is exported here (not via a VAR=val call-site prefix, whose
	# propagation through function calls is shell-dependent) so the
	# stubs - and the fake stat used for the mount simulation - are
	# reliably found by the tool and its children.
	PATH="$work/bin:$PATH"
	export PATH
	mkdir -p "$work/tmp" || return 1
	SAPHIRA_APK="$work/bin/apk-stub" \
	SAPHIRA_ID="$work/bin/id-stub" \
	SAPHIRA_PROFILE_ROOT="$work/profiles" \
	SAPHIRA_REPOSITORY="test-repo" \
	SAPHIRA_TMPDIR="$work/tmp" \
	TMPDIR="$work/tmp" \
	sh "$tool" "$@" >"$work/out" 2>"$work/err"
}

no_emptiness_refusal()
{
	! grep -q 'target is not empty' "$work/err"
}

printf '%s\n' '# empty targets pass the gate'

t=$work/t-empty; mkdir -p "$t/lost+found"
if run_boot "$t" testprofile && [ -f "$t/etc/apk/repositories" ]; then
	ok 'empty directory assembles past the gate'
elif no_emptiness_refusal; then
	ok 'empty directory passes the gate (later stage, as expected without a real rootfs)'
else
	bad "empty directory refused at the gate: $(cat "$work/err")"
fi

printf '%s\n' '# real content is still refused'

t=$work/t-full; mkdir -p "$t"; printf 'x\n' > "$t/file"
if run_boot "$t" testprofile; then
	bad 'directory with content assembled without refusal'
elif grep -q 'target is not empty' "$work/err"; then
	ok 'directory with content refused at the gate'
else
	bad "wrong failure for content: $(cat "$work/err")"
fi

printf '%s\n' '# caller-owned mounts are scaffolding, not content'

t=$work/t-mnt; mkdir -p "$t/lost+found" "$t/boot" "$t/boot/lost+found"
otherdev=$(stat -c %d /dev/shm 2>/dev/null || true)
workdev=$(stat -c %d "$work" 2>/dev/null || true)
if [ -n "$otherdev" ] && [ "$otherdev" != "$workdev" ]; then
	cat > "$work/bin/stat" <<EOF
#!/bin/sh
if [ "\$1" = "-c" ] && [ "\$2" = "%d" ]; then
	case \$3 in
	"$t/boot"|"$t/boot/"*) printf '%s\n' "$otherdev" ;;
	*) exec /bin/stat "\$@" ;;
	esac
else
	exec /bin/stat "\$@"
fi
EOF
	chmod +x "$work/bin/stat"
	run_boot "$t" testprofile
	rc=$?
	if [ $rc -eq 0 ] && [ -f "$t/etc/apk/repositories" ]; then
		ok 'mounted /boot passes the gate and assembles'
	elif [ $rc -ne 0 ] && no_emptiness_refusal; then
		ok 'mounted /boot passes the gate (later stage, as expected without a real rootfs)'
	else
		bad "mounted /boot refused at the gate: $(cat "$work/err")"
	fi
	rm -f "$work/bin/stat"
else
	ok 'mounted-/boot case skipped (no second device visible here)'
fi

if [ "$failures" -ne 0 ]; then
	printf 'bootstrap-target-emptiness: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'bootstrap-target-emptiness tests: OK'
