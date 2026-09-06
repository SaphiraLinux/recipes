#!/bin/sh
# installpkg tests: NVR-pinned install semantics without touching the host.
# Fixture bin/ provides: id (claims uid 0), checkpkg (always verifies),
# apk (canned multi-version index, real `version -t` comparison, recorded
# add atom, emulated installed-version check). Proves installpkg resolves
# the newest indexed NVR (middle entry, not first/last), pins the add
# atom to it, and dies when the installed version is not the intended one.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s INSTALLPKG\n' "$0" >&2
	exit 1
}

installpkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$installpkg")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-installpkg-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/repo/gen/x86_64" "$test_root/state"

printf '%s\n' 'placeholder index (content served by fixture apk)' \
	> "$test_root/repo/gen/x86_64/Packages.adb"

printf '%s\n' '#!/bin/sh' 'echo 0' > "$test_root/bin/id"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_root/bin/checkpkg"
cat > "$test_root/bin/apk" <<'FIXTURE'
#!/bin/sh
# fixture apk: see tests/installpkg.sh header.
if [ "$1" = "adbdump" ]; then cat "$FIXTURE_STATE/index.adb"; exit 0; fi
if [ "$1" = "version" ]; then shift; exec /usr/bin/apk version "$@"; fi
prev=""
for arg in "$@"; do
	if [ "$prev" = "add" ]; then printf '%s\n' "$arg" > "$FIXTURE_STATE/add-atom"; exit 0; fi
	prev=$arg
done
if [ "$1" = "info" ] && [ "$2" = "-e" ]; then
	[ "${INFO_E_FAIL-}" != 1 ] || exit 1
	[ "$3" = "$(cat "$FIXTURE_STATE/add-atom")" ] || exit 1
	exit 0
fi
exit 1
FIXTURE
chmod +x "$test_root/bin/id" "$test_root/bin/checkpkg" "$test_root/bin/apk"

# Newest NVR sits in the middle: first-match would pick r35, last-match
# r36; only a real max picks r37.
cat > "$test_root/state/index.adb" <<'INDEX'
  - name: other-pkg
    version: 2.0-r1
    hashes: 00
  - name: saphira-widget
    version: 1.0-r35
    hashes: 11
  - name: saphira-widget
    version: 1.0-r37
    hashes: 22
  - name: saphira-widget
    version: 1.0-r36
    hashes: 33
INDEX

run_installer()
{
	PATH="$test_root/bin:$PATH" \
	FIXTURE_STATE=$test_root/state \
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BINDIR=$test_root/bin \
	SAPHIRA_APK=$test_root/bin/apk \
	SAPHIRA_REPO_DIR=$test_root/repo \
	SAPHIRA_REPO_NAMES=gen \
	SAPHIRA_ARCH=x86_64 \
		"$installpkg" "$@"
}

# Newest indexed NVR wins and the add atom is pinned to it.
run_installer saphira-widget > "$test_root/ok.out" 2> "$test_root/ok.err"
[ "$(cat "$test_root/state/add-atom")" = "saphira-widget=1.0-r37" ]
grep 'installpkg: installed saphira-widget-1.0-r37' "$test_root/ok.out" >/dev/null

# Installed version diverging from the intended NVR is fatal.
if INFO_E_FAIL=1 run_installer saphira-widget > "$test_root/mismatch.out" 2> "$test_root/mismatch.err"; then
	printf '%s\n' 'version mismatch unexpectedly installed' >&2
	exit 1
fi
grep 'not the intended NVR: saphira-widget-1.0-r37' "$test_root/mismatch.err" >/dev/null

# A name absent from the index is refused before any apk mutation.
rm -f "$test_root/state/add-atom"
if run_installer nosuchpkg > "$test_root/absent.out" 2> "$test_root/absent.err"; then
	printf '%s\n' 'absent package unexpectedly installed' >&2
	exit 1
fi
grep 'not present in Packages.adb: nosuchpkg' "$test_root/absent.err" >/dev/null
test ! -e "$test_root/state/add-atom"

printf '%s\n' 'installpkg NVR pinning, mismatch refusal, and absent-package refusal tests: OK'
