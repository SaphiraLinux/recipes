#!/bin/bash
# saphira-install target acceptance: the empty-target guard must
# tolerate the orchestrator's own mounts.
#
# install-to-disk mounts the root filesystem and then, for explicit
# --boot-size (and always for zfs roots), a separate ext4 /boot at
# $target/boot BEFORE invoking saphira-install, so kernel and
# bootloader files land in it. The target therefore legitimately
# contains a mountpoint when assembly starts, and the guard must not
# mistake the caller's scaffolding for installed content
# (proven: every --boot-size install died with "target is not empty",
# and --reinstall died trying to rm -rf the live mountpoint).
#
# Everything here runs unprivileged in scratch directories, with stub
# assembler/genfstab commands standing in for the real ones via the
# tool's SAPHIRA_ASSEMBLER / SAPHIRA_GENFSTAB seams. Mount points are
# simulated with symlinks onto a different device, which exercises the
# same st_dev comparison the tool uses to recognise them (creating
# real mounts would need privileges the test must never require).

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
tool=${SAPHIRA_INSTALL:-$root/files/saphira-install}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/profiles"
cat > "$work/bin/assembler" <<'EOF'
#!/bin/sh
touch "$1/STUB-RAN"
EOF
cat > "$work/bin/genfstab" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/assembler" "$work/bin/genfstab"
printf '# test profile intentions\n' > "$work/profiles/testprofile"

run_install()
{
	# run_install <target> [extra args...]: assemble with stubs.
	SAPHIRA_ASSEMBLER="$work/bin/assembler" \
	SAPHIRA_GENFSTAB="$work/bin/genfstab" \
	SAPHIRA_PROFILE_ROOT="$work/profiles" \
	sh "$tool" --target "$1" --profile testprofile "${@:2}" \
		>"$work/out" 2>"$work/err"
}

printf '%s\n' '# empty targets assemble'

t=$work/t-empty; mkdir -p "$t"
if run_install "$t" && [ -f "$t/STUB-RAN" ]; then
	ok 'empty directory assembles'
else
	bad "empty directory refused: $(cat "$work/err")"
fi

printf '%s\n' '# lost+found alone is not content'

t=$work/t-lost; mkdir -p "$t/lost+found"
if run_install "$t" && [ -f "$t/STUB-RAN" ]; then
	ok 'lost+found alone assembles'
else
	bad "lost+found alone refused: $(cat "$work/err")"
fi

printf '%s\n' '# real content still refuses without --reinstall'

t=$work/t-full; mkdir -p "$t"; printf 'x\n' > "$t/file"
if run_install "$t"; then
	bad 'directory with content assembled without --reinstall'
else
	ok 'directory with content refused without --reinstall'
fi
t=$work/t-subdir; mkdir -p "$t/lost+found" "$t/subdir"
if run_install "$t"; then
	bad 'directory with a same-device subdir assembled without --reinstall'
else
	ok 'directory with a same-device subdir refused (unmounted mountpoint is a misconfiguration)'
fi

printf '%s\n' '# caller-owned mounts are scaffolding, not content'

# A real mountpoint is recognised by its device: stat reports the
# mounted filesystem, not the covered directory. Symlinks are still
# content (strict: only true mounts are skipped). A bind mount cannot
# simulate this (same filesystem, same device), so the test fakes
# stat itself on PATH: everything at or under the fake mountpoint
# reports a different device, exactly as a separately mounted /boot
# would, while every other path delegates to the real stat.
# (The orchestrator always mounts a freshly mkfs'd separate
# filesystem here, never a bind mount.)
t=$work/t-mnt; mkdir -p "$t/lost+found" "$t/boot" "$t/boot/lost+found"
otherdev=$(stat -c %d /dev/shm 2>/dev/null || true)
workdev=$(stat -c %d "$work")
realstat=$(command -v stat)
if [ -n "$otherdev" ] && [ "$otherdev" != "$workdev" ]; then
cat > "$work/bin/stat" <<EOF
#!/bin/sh
if [ "\$1" = "-c" ] && [ "\$2" = "%d" ]; then
	case \$3 in
	"$t/boot"|"$t/boot/"*) printf '%s\n' "$otherdev" ;;
	*) exec $realstat "\$@" ;;
	esac
else
	exec $realstat "\$@"
fi
EOF
chmod +x "$work/bin/stat"
if PATH="$work/bin:$PATH" run_install "$t" && [ -f "$t/STUB-RAN" ]; then
	ok 'mounted /boot assembles'
else
	bad "mounted /boot refused: $(cat "$work/err")"
fi
printf 'x\n' > "$t/file"
if PATH="$work/bin:$PATH" run_install "$t" --reinstall && [ -f "$t/STUB-RAN" ] && [ ! -e "$t/file" ] && [ -d "$t/boot" ]; then
	ok '--reinstall clears own files and leaves the mount alone'
else
	bad "--reinstall with mount misbehaved: $(cat "$work/err")"
fi
rm -f "$work/bin/stat"
else
	ok 'mounted-/boot case skipped (no second device visible here)'
fi
t=$work/t-link; mkdir -p "$t/lost+found"
printf 'x\n' > "$t/real"
ln -s "$t/real" "$t/boot"
if run_install "$t"; then
	bad 'symlink at top level assembled (links are content, not mounts)'
else
	ok 'symlink at top level refused (only true mounts are skipped)'
fi

printf '%s\n' '# --reinstall clears and assembles'

t=$work/t-re; mkdir -p "$t/lost+found" "$t/sub"
printf 'x\n' > "$t/file"; printf 'x\n' > "$t/sub/file"
if run_install "$t" --reinstall && [ -f "$t/STUB-RAN" ] && [ ! -e "$t/file" ] && [ ! -e "$t/sub" ]; then
	ok '--reinstall wipes own content and assembles'
else
	bad "--reinstall failed: $(cat "$work/err")"
fi

if [ "$failures" -ne 0 ]; then
	printf 'install-target-emptiness: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'install-target-emptiness tests: OK'
