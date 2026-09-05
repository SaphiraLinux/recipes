#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s MAKEPKG\n' "$0" >&2
	exit 1
}

makepkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$makepkg")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-makepkg-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
stage=$test_root/stage
artifacts=$test_root/artifacts
package_tmp=$test_root/package-tmp
mkdir -p "$stage" "$artifacts" "$package_tmp" "$test_root/bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "sudo must not run" >&2' 'exit 99' > "$test_root/bin/sudo"
chmod 755 "$test_root/bin/sudo"

host_before=$(sha256sum /lib/apk/db/installed /etc/apk/world)
repo_before=$(find /out/stage4/packages/x86_64 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | sha256sum)

write_manifest()
{
	producer=$1
	outputs=$2
	mkdir -p "$stage/$producer"
	printf '%s\n' "$outputs" > "$stage/$producer/manifest.json"
}

run_makepkg()
{
	producer=$1
	shift
	PATH=$test_root/bin:/usr/bin:/bin \
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage \
	SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$package_tmp \
	SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot \
		"$makepkg" "$producer" "$@"
}

mkdir -p "$stage/make/pkg/usr/bin" "$stage/make/subpkg/make-doc/usr/share/doc/make"
printf '%s\n' make > "$stage/make/pkg/usr/bin/make"
printf '%s\n' manual > "$stage/make/subpkg/make-doc/usr/share/doc/make/README"
write_manifest make '{"arch":"x86_64","build_time":1,"license":"GPL-3.0-or-later","name":"make","origin":"make","outputs":[{"dependencies":[],"description":"GNU make","name":"make","payload":"pkg"},{"dependencies":["make=4.4.1-r0"],"description":"GNU make documentation","name":"make-doc","payload":"subpkg/make-doc"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/make/","version":"4.4.1-r0"}'
run_makepkg make

test -f "$artifacts/x86_64/make-4.4.1-r0.apk"
test -f "$artifacts/x86_64/make-doc-4.4.1-r0.apk"
apk verify --allow-untrusted "$artifacts/x86_64/make-4.4.1-r0.apk"
apk adbdump "$artifacts/x86_64/make-4.4.1-r0.apk" | grep 'user: root' >/dev/null
apk adbdump "$artifacts/x86_64/make-doc-4.4.1-r0.apk" | grep 'make=4.4.1-r0' >/dev/null
python3 - "$stage/make/artifact-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
assert receipt["schema"] == "saphira-artifact-manifest/v1"
assert receipt["constructor"] == "makepkg"
assert receipt["producer"] == "make"
assert {item["name"] for item in receipt["artifacts"]} == {"make", "make-doc"}
assert {item["backend"] for item in receipt["artifacts"]} == {"userns-maproot"}
PY

# The same canonical constructor packages fakeroot itself.
mkdir -p "$stage/fakeroot/pkg/usr/bin"
printf '%s\n' fakeroot > "$stage/fakeroot/pkg/usr/bin/fakeroot"
write_manifest fakeroot '{"arch":"x86_64","build_time":2,"license":"GPL-3.0-or-later","name":"fakeroot","origin":"fakeroot","outputs":[{"dependencies":[],"description":"fakeroot","name":"fakeroot","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://salsa.debian.org/clint/fakeroot","version":"2.1.4-r0"}'
run_makepkg fakeroot
test -f "$artifacts/x86_64/fakeroot-2.1.4-r0.apk"

# An ordinary package uses exactly the same canonical backend.
mkdir -p "$stage/ordinary/pkg/usr/bin"
printf '%s\n' ordinary > "$stage/ordinary/pkg/usr/bin/ordinary"
write_manifest ordinary '{"arch":"x86_64","build_time":3,"license":"MIT","name":"ordinary","origin":"ordinary","outputs":[{"dependencies":[],"description":"ordinary","name":"ordinary","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg ordinary
test -f "$artifacts/x86_64/ordinary-1-r0.apk"
apk adbdump "$artifacts/x86_64/ordinary-1-r0.apk" | grep 'user: root' >/dev/null

# Payloads cannot escape through symlinks and may never create lib64.
mkdir -p "$stage/escape/pkg/usr/lib"
ln -s ../../../../egg "$stage/escape/pkg/usr/lib/escape"
write_manifest escape '{"arch":"x86_64","build_time":4,"license":"MIT","name":"escape","origin":"escape","outputs":[{"dependencies":[],"description":"escape","name":"escape","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg escape > "$test_root/escape.log" 2>&1; then
	printf '%s\n' 'escaping payload symlink unexpectedly packaged' >&2
	exit 1
fi
grep 'escapes transaction' "$test_root/escape.log" >/dev/null

mkdir -p "$stage/lib64-test/pkg/usr/lib64"
printf '%s\n' forbidden > "$stage/lib64-test/pkg/usr/lib64/forbidden"
write_manifest lib64-test '{"arch":"x86_64","build_time":5,"license":"MIT","name":"lib64-test","origin":"lib64-test","outputs":[{"dependencies":[],"description":"lib64-test","name":"lib64-test","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg lib64-test > "$test_root/lib64.log" 2>&1; then
	printf '%s\n' 'lib64 payload unexpectedly packaged' >&2
	exit 1
fi
grep '/lib-only layout' "$test_root/lib64.log" >/dev/null

host_after=$(sha256sum /lib/apk/db/installed /etc/apk/world)
[ "$host_before" = "$host_after" ]
[ "$repo_before" = "$(find /out/stage4/packages/x86_64 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | sha256sum)" ]
printf '%s\n' 'canonical makepkg metadata, ownership, and safety tests: OK'

# Setuid/setgid payload bits must survive the rootless chown (sudo setuid
# incident): recipe chmods 4755, chown -R 0:0 must not strip them.
mkdir -p "$stage/setuid/pkg/usr/bin" "$stage/setuid/pkg/var/lib/shared"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$stage/setuid/pkg/usr/bin/setuid-tool"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$stage/setuid/pkg/usr/bin/plain-tool"
chmod 4755 "$stage/setuid/pkg/usr/bin/setuid-tool"
chmod 755 "$stage/setuid/pkg/usr/bin/plain-tool"
chmod 2775 "$stage/setuid/pkg/var/lib/shared"
printf '%s\n' keep > "$stage/setuid/pkg/var/lib/shared/.keep"
write_manifest setuid '{"arch":"x86_64","build_time":6,"license":"MIT","name":"setuid","origin":"setuid","outputs":[{"dependencies":[],"description":"setuid","name":"setuid","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg setuid
apk adbdump "$artifacts/x86_64/setuid-1-r0.apk" | grep -A2 'name: setuid-tool' | grep 'mode: 04755' >/dev/null
apk adbdump "$artifacts/x86_64/setuid-1-r0.apk" | grep -A2 'name: plain-tool' | grep 'mode: 0755' >/dev/null
apk adbdump "$artifacts/x86_64/setuid-1-r0.apk" | grep -A2 'name: var/lib/shared' | grep 'mode: 02775' >/dev/null
printf '%s\n' 'setuid preservation: ok (file 4755, dir 2775, plain 755)'

# replaces metadata must survive the manifest -> APK round trip: a
# superseding package names the packages whose payload files it may take
# over on upgrade (apk-tools v3 overwrite-without-warning semantics; the
# expat vs Stage4 libexpat upgrade collision).
mkdir -p "$stage/supersede/pkg/usr/bin"
printf '%s\n' supersede > "$stage/supersede/pkg/usr/bin/supersede"
write_manifest supersede '{"arch":"x86_64","build_time":7,"license":"MIT","name":"supersede","origin":"supersede","outputs":[{"dependencies":[],"description":"supersede","name":"supersede","payload":"pkg"}],"replaces":["libold"],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg supersede
test -f "$artifacts/x86_64/supersede-1-r0.apk"
apk adbdump "$artifacts/x86_64/supersede-1-r0.apk" | grep -A1 'replaces:' | grep 'libold' >/dev/null
printf '%s\n' 'replaces metadata round-trip: ok (manifest -> APK info block)'
