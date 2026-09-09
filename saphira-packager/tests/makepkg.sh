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

# Account fragments generate thin install scripts: a fragment
# accounts.d/<name> is validated, recorded in the receipt, embedded as
# post-install/post-upgrade callers, and pulls the helper dependency.
mkdir -p "$stage/idsvc/pkg/usr/bin" "$stage/idsvc/pkg/usr/share/saphira/accounts.d"
printf '%s\n' idsvc > "$stage/idsvc/pkg/usr/bin/idsvc"
printf '%s\n' 'user iduser 660 idgroup /var/lib/idsvc /sbin/nologin' 'group idgroup 660' 'dir /var/lib/idsvc 0755 iduser idgroup' > "$stage/idsvc/pkg/usr/share/saphira/accounts.d/idsvc"
write_manifest idsvc '{"arch":"x86_64","build_time":8,"license":"MIT","name":"idsvc","origin":"idsvc","outputs":[{"dependencies":[],"description":"idsvc","name":"idsvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg idsvc
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'post-install' >/dev/null
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'post-upgrade' >/dev/null
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'post-deinstall' >/dev/null
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'saphira-baselayout' >/dev/null
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'ensure-identity.sh' >/dev/null
# The deinstall caller embeds the validated declaration (apk runs it
# after the payload fragment is gone) and invokes disable mode.
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'ensure-identity.sh --disable' >/dev/null
apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep 'user iduser 660 idgroup' >/dev/null
# Install/upgrade callers must not carry the disable flag.
if apk adbdump "$artifacts/x86_64/idsvc-1-r0.apk" | grep -A6 'post-install:' | grep -q -- '--disable'; then
	printf '%s\n' 'disable flag leaked into post-install caller' >&2
	exit 1
fi
python3 - "$stage/idsvc/artifact-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
accounts = receipt["artifacts"][0]["accounts"]
assert accounts["users"] == [{"name": "iduser", "uid": "660", "primary": "idgroup", "home": "/var/lib/idsvc", "shell": "/sbin/nologin"}], accounts
assert accounts["groups"] == [{"name": "idgroup", "gid": "660"}], accounts
assert accounts["dirs"] == [{"path": "/var/lib/idsvc", "mode": "0755", "owner": "iduser", "group": "idgroup"}], accounts
PY
printf '%s\n' 'account fragment round-trip: ok (scripts, helper depends, receipt)'

# Malformed fragments and foreign fragments fail the build.
mkdir -p "$stage/badfrag/pkg/usr/bin" "$stage/badfrag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' badfrag > "$stage/badfrag/pkg/usr/bin/badfrag"
printf '%s\n' 'user badfrag notanid badgroup /var/lib/bad /sbin/nologin' > "$stage/badfrag/pkg/usr/share/saphira/accounts.d/badfrag"
write_manifest badfrag '{"arch":"x86_64","build_time":9,"license":"MIT","name":"badfrag","origin":"badfrag","outputs":[{"dependencies":[],"description":"badfrag","name":"badfrag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg badfrag > "$test_root/badfrag.log" 2>&1; then
	printf '%s\n' 'malformed account fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'UID must be 0..887' "$test_root/badfrag.log" >/dev/null
mkdir -p "$stage/strayfrag/pkg/usr/bin" "$stage/strayfrag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' strayfrag > "$stage/strayfrag/pkg/usr/bin/strayfrag"
printf '%s\n' 'group someoneelse 661' > "$stage/strayfrag/pkg/usr/share/saphira/accounts.d/someoneelse"
write_manifest strayfrag '{"arch":"x86_64","build_time":10,"license":"MIT","name":"strayfrag","origin":"strayfrag","outputs":[{"dependencies":[],"description":"strayfrag","name":"strayfrag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg strayfrag > "$test_root/strayfrag.log" 2>&1; then
	printf '%s\n' 'foreign account fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'foreign account fragments' "$test_root/strayfrag.log" >/dev/null
printf '%s\n' 'account fragment refusal: ok (malformed, foreign)'

# Identities outside the packaged range (888..999 local, 1000+ human)
# fail the build with the range named.
mkdir -p "$stage/bigrange/pkg/usr/bin" "$stage/bigrange/pkg/usr/share/saphira/accounts.d"
printf '%s\n' bigrange > "$stage/bigrange/pkg/usr/bin/bigrange"
printf '%s\n' 'user biguser 900 biggroup /var/lib/big /sbin/nologin' 'group biggroup 900' > "$stage/bigrange/pkg/usr/share/saphira/accounts.d/bigrange"
write_manifest bigrange '{"arch":"x86_64","build_time":11,"license":"MIT","name":"bigrange","origin":"bigrange","outputs":[{"dependencies":[],"description":"bigrange","name":"bigrange","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg bigrange > "$test_root/bigrange.log" 2>&1; then
	printf '%s\n' 'out-of-range account fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'must be 0..887' "$test_root/bigrange.log" >/dev/null
printf '%s\n' 'account range refusal: ok (UID/GID 888+ rejected)'

# Reserved identities (root/wheel/ID 0, or a service anchored to
# root/wheel) fail the build: root belongs to the base seed and
# firstboot, never to a package.
mkdir -p "$stage/rootfrag/pkg/usr/bin" "$stage/rootfrag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' rootfrag > "$stage/rootfrag/pkg/usr/bin/rootfrag"
printf '%s\n' 'user root 0 root /root /bin/bash' 'group root 0' > "$stage/rootfrag/pkg/usr/share/saphira/accounts.d/rootfrag"
write_manifest rootfrag '{"arch":"x86_64","build_time":13,"license":"MIT","name":"rootfrag","origin":"rootfrag","outputs":[{"dependencies":[],"description":"rootfrag","name":"rootfrag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg rootfrag > "$test_root/rootfrag.log" 2>&1; then
	printf '%s\n' 'root fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'reserved system identity' "$test_root/rootfrag.log" >/dev/null
mkdir -p "$stage/zerofrag/pkg/usr/bin" "$stage/zerofrag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' zerofrag > "$stage/zerofrag/pkg/usr/bin/zerofrag"
printf '%s\n' 'user toor 0 toor /var/empty /sbin/nologin' 'group toor 1' > "$stage/zerofrag/pkg/usr/share/saphira/accounts.d/zerofrag"
write_manifest zerofrag '{"arch":"x86_64","build_time":14,"license":"MIT","name":"zerofrag","origin":"zerofrag","outputs":[{"dependencies":[],"description":"zerofrag","name":"zerofrag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg zerofrag > "$test_root/zerofrag.log" 2>&1; then
	printf '%s\n' 'UID-0 fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'reserved system identity' "$test_root/zerofrag.log" >/dev/null
printf '%s\n' 'account reserved-identity refusal: ok (root/wheel/ID 0)'
# Foundational group reservations are typed: spokes/wheel/root names
# and GIDs 0/1/2 refuse under any name.
mkdir -p "$stage/spokesfrag/pkg/usr/bin" "$stage/spokesfrag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' spokesfrag > "$stage/spokesfrag/pkg/usr/bin/spokesfrag"
printf '%s\n' 'group spokes 2' > "$stage/spokesfrag/pkg/usr/share/saphira/accounts.d/spokesfrag"
write_manifest spokesfrag '{"arch":"x86_64","build_time":15,"license":"MIT","name":"spokesfrag","origin":"spokesfrag","outputs":[{"dependencies":[],"description":"spokesfrag","name":"spokesfrag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg spokesfrag > "$test_root/spokesfrag.log" 2>&1; then
	printf '%s\n' 'spokes fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/spokesfrag.log" >/dev/null
mkdir -p "$stage/gid1frag/pkg/usr/bin" "$stage/gid1frag/pkg/usr/share/saphira/accounts.d"
printf '%s\n' gid1frag > "$stage/gid1frag/pkg/usr/bin/gid1frag"
printf '%s\n' 'group shadowsys 1' > "$stage/gid1frag/pkg/usr/share/saphira/accounts.d/gid1frag"
write_manifest gid1frag '{"arch":"x86_64","build_time":16,"license":"MIT","name":"gid1frag","origin":"gid1frag","outputs":[{"dependencies":[],"description":"gid1frag","name":"gid1frag","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg gid1frag > "$test_root/gid1frag.log" 2>&1; then
	printf '%s\n' 'GID-1 fragment unexpectedly packaged' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/gid1frag.log" >/dev/null
printf '%s\n' 'account foundation-group refusal: ok (spokes/wheel/GID 0-2)'

# Identities in the 200..887 expansion range build fine but earn a
# loud notice (the fragment must document the exception).
mkdir -p "$stage/midrange/pkg/usr/bin" "$stage/midrange/pkg/usr/share/saphira/accounts.d"
printf '%s\n' midrange > "$stage/midrange/pkg/usr/bin/midrange"
printf '%s\n' '# documented exception fixture' 'user miduser 250 midgroup /var/lib/mid /sbin/nologin' 'group midgroup 250' > "$stage/midrange/pkg/usr/share/saphira/accounts.d/midrange"
write_manifest midrange '{"arch":"x86_64","build_time":12,"license":"MIT","name":"midrange","origin":"midrange","outputs":[{"dependencies":[],"description":"midrange","name":"midrange","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if ! run_makepkg midrange > "$test_root/midrange.log" 2>&1; then
	printf '%s\n' 'expansion-range account fragment unexpectedly refused' >&2
	exit 1
fi
grep 'expansion range' "$test_root/midrange.log" >/dev/null
printf '%s\n' 'account expansion notice: ok (200..887 builds with notice)'
