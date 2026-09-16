#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s MAKEPKG\n' "$0" >&2
	exit 1
}

makepkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$makepkg")/../.." && pwd)
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-makepkg-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
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

# Installed symlinks may never point into the constructor workspace:
# /build is build-time state and must not leak into APKs (precedent:
# kernel modules_install baking /build/<pkg>/... into
# /lib/modules/*/build, bzip2 install rules baking /build/<pkg>/...
# into /usr/bin helpers). Relative links are unaffected.
mkdir -p "$stage/workspace-leak/pkg/lib/modules/7.2.2"
ln -s /build/saphira-kernel/source/linux-7.2.2 "$stage/workspace-leak/pkg/lib/modules/7.2.2/build"
write_manifest workspace-leak '{"arch":"x86_64","build_time":6,"license":"MIT","name":"workspace-leak","origin":"workspace-leak","outputs":[{"dependencies":[],"description":"workspace leak","name":"workspace-leak","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg workspace-leak > "$test_root/workspace-leak.log" 2>&1; then
	printf '%s\n' 'constructor-workspace symlink unexpectedly packaged' >&2
	exit 1
fi
grep 'points into constructor workspace /build in workspace-leak' "$test_root/workspace-leak.log" >/dev/null
grep 'lib/modules/7.2.2/build -> /build/saphira-kernel/source/linux-7.2.2' "$test_root/workspace-leak.log" >/dev/null

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

# sysusers stanza: a fragment with no census declares native account
# management; install/upgrade callers run the reconciler then
# systemd-sysusers, deinstall stays reconciler-only.
mkdir -p "$stage/sysvc/pkg/usr/bin" "$stage/sysvc/pkg/usr/share/saphira/accounts.d"
printf '%s\n' sysvc > "$stage/sysvc/pkg/usr/bin/sysvc"
printf '%s\n' '# native accounts live in sysusers.d' 'sysusers' > "$stage/sysvc/pkg/usr/share/saphira/accounts.d/sysvc"
write_manifest sysvc '{"arch":"x86_64","build_time":8,"license":"MIT","name":"sysvc","origin":"sysvc","outputs":[{"dependencies":[],"description":"sysvc","name":"sysvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg sysvc
apk adbdump "$artifacts/x86_64/sysvc-1-r0.apk" | grep -A10 'post-install:' | grep '/usr/bin/systemd-sysusers' >/dev/null
apk adbdump "$artifacts/x86_64/sysvc-1-r0.apk" | grep -A10 'post-upgrade:' | grep '/usr/bin/systemd-sysusers' >/dev/null
apk adbdump "$artifacts/x86_64/sysvc-1-r0.apk" | grep -A10 'post-install:' | grep 'ensure-identity.sh' >/dev/null
if apk adbdump "$artifacts/x86_64/sysvc-1-r0.apk" | grep -A20 'post-deinstall:' | grep -q 'systemd-sysusers'; then
	printf '%s\n' 'sysusers leaked into post-deinstall caller' >&2
	exit 1
fi
mkdir -p "$stage/dupsy/pkg/usr/bin" "$stage/dupsy/pkg/usr/share/saphira/accounts.d"
printf '%s\n' dupsy > "$stage/dupsy/pkg/usr/bin/dupsy"
printf '%s\n' 'sysusers' 'sysusers' > "$stage/dupsy/pkg/usr/share/saphira/accounts.d/dupsy"
write_manifest dupsy '{"arch":"x86_64","build_time":8,"license":"MIT","name":"dupsy","origin":"dupsy","outputs":[{"dependencies":[],"description":"dupsy","name":"dupsy","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg dupsy > "$test_root/dupsy.log" 2>&1; then
	printf '%s\n' 'duplicate sysusers stanza unexpectedly packaged' >&2
	exit 1
fi
grep 'duplicate sysusers stanza' "$test_root/dupsy.log" >/dev/null
printf '%s\n' 'account sysusers stanza: ok (install callers, deinstall clean, duplicate refused)'

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

# File stanzas bind install-time ownership to payload files: declared
# owner plus the root built-in, validated, payload-bound, recorded in
# the receipt, scripts generated with the helper dependency.
mkdir -p "$stage/filesvc/pkg/usr/bin" "$stage/filesvc/pkg/usr/share/saphira/accounts.d"
printf '%s\n' filesvc > "$stage/filesvc/pkg/usr/bin/filesvc"
printf '%s\n' queuebinary > "$stage/filesvc/pkg/usr/bin/filesvc-queue"
printf '%s\n' 'user fuser 664 fgroup /var/lib/filesvc /sbin/nologin' 'group fgroup 664' 'file /usr/bin/filesvc-queue 04711 fuser fgroup' 'file /usr/bin/filesvc 0755 root root' > "$stage/filesvc/pkg/usr/share/saphira/accounts.d/filesvc"
write_manifest filesvc '{"arch":"x86_64","build_time":17,"license":"MIT","name":"filesvc","origin":"filesvc","outputs":[{"dependencies":[],"description":"filesvc","name":"filesvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg filesvc
apk adbdump "$artifacts/x86_64/filesvc-1-r0.apk" | grep 'post-install' >/dev/null
apk adbdump "$artifacts/x86_64/filesvc-1-r0.apk" | grep 'post-upgrade' >/dev/null
apk adbdump "$artifacts/x86_64/filesvc-1-r0.apk" | grep 'post-deinstall' >/dev/null
apk adbdump "$artifacts/x86_64/filesvc-1-r0.apk" | grep 'saphira-baselayout' >/dev/null
python3 - "$stage/filesvc/artifact-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
accounts = receipt["artifacts"][0]["accounts"]
assert accounts["files"] == [{"path": "/usr/bin/filesvc-queue", "mode": "04711", "owner": "fuser", "group": "fgroup"}, {"path": "/usr/bin/filesvc", "mode": "0755", "owner": "root", "group": "root"}], accounts
PY
printf '%s\n' 'account file stanza round-trip: ok (payload-bound, receipt, scripts)'

# Malformed file stanzas fail the build: relative path, bad mode,
# missing payload target, symlink target, directory target, numeric
# owner reference.
filebad()
{
	name=$1
	fragment=$2
	message=$3
	mkdir -p "$stage/$name/pkg/usr/bin" "$stage/$name/pkg/usr/share/saphira/accounts.d"
	printf '%s\n' "$name" > "$stage/$name/pkg/usr/bin/$name"
	printf '%s\n' payloadfile > "$stage/$name/pkg/usr/bin/payloadfile"
	printf '%s\n' 'user fbaduser 665 fbadgroup /var/lib/fbad /sbin/nologin' 'group fbadgroup 665' "$fragment" > "$stage/$name/pkg/usr/share/saphira/accounts.d/$name"
	write_manifest "$name" '{"arch":"x86_64","build_time":18,"license":"MIT","name":"'"$name"'","origin":"'"$name"'","outputs":[{"dependencies":[],"description":"'"$name"'","name":"'"$name"'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
	if run_makepkg "$name" > "$test_root/$name.log" 2>&1; then
		printf '%s\n' "file stanza $name unexpectedly packaged" >&2
		exit 1
	fi
	grep "$message" "$test_root/$name.log" >/dev/null
}
filebad filerel 'file var/rel 0644 fbaduser fbadgroup' 'must be absolute and normalized'
filebad filemode 'file /usr/bin/payloadfile 0999 fbaduser fbadgroup' 'invalid mode'
filebad filemissing 'file /usr/bin/absent 0644 fbaduser fbadgroup' 'missing from the payload'
filebad filenumeric 'file /usr/bin/payloadfile 0644 665 fbadgroup' 'not a number'
mkdir -p "$stage/filesymlink/pkg/usr/bin" "$stage/filesymlink/pkg/usr/share/saphira/accounts.d"
printf '%s\n' filesymlink > "$stage/filesymlink/pkg/usr/bin/filesymlink"
printf '%s\n' payloadfile > "$stage/filesymlink/pkg/usr/bin/payloadfile"
ln -s payloadfile "$stage/filesymlink/pkg/usr/bin/linkfile"
printf '%s\n' 'user fbaduser 665 fbadgroup /var/lib/fbad /sbin/nologin' 'group fbadgroup 665' 'file /usr/bin/linkfile 0644 fbaduser fbadgroup' > "$stage/filesymlink/pkg/usr/share/saphira/accounts.d/filesymlink"
write_manifest filesymlink '{"arch":"x86_64","build_time":18,"license":"MIT","name":"filesymlink","origin":"filesymlink","outputs":[{"dependencies":[],"description":"filesymlink","name":"filesymlink","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg filesymlink > "$test_root/filesymlink.log" 2>&1; then
	printf '%s\n' 'symlink file target unexpectedly packaged' >&2
	exit 1
fi
grep 'is a symlink' "$test_root/filesymlink.log" >/dev/null
mkdir -p "$stage/filedir/pkg/usr/bin" "$stage/filedir/pkg/usr/share/saphira/accounts.d"
printf '%s\n' filedir > "$stage/filedir/pkg/usr/bin/filedir"
printf '%s\n' 'user fbaduser 665 fbadgroup /var/lib/fbad /sbin/nologin' 'group fbadgroup 665' 'file /usr/bin 0755 fbaduser fbadgroup' > "$stage/filedir/pkg/usr/share/saphira/accounts.d/filedir"
write_manifest filedir '{"arch":"x86_64","build_time":18,"license":"MIT","name":"filedir","origin":"filedir","outputs":[{"dependencies":[],"description":"filedir","name":"filedir","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg filedir > "$test_root/filedir.log" 2>&1; then
	printf '%s\n' 'directory file target unexpectedly packaged' >&2
	exit 1
fi
grep 'is a directory' "$test_root/filedir.log" >/dev/null
# Fifos and other specials cannot ship in APK payloads (the
# constructor archives regular files only): refused with guidance.
mkdir -p "$stage/filefifo/pkg/usr/bin" "$stage/filefifo/pkg/usr/share/saphira/accounts.d"
printf '%s\n' filefifo > "$stage/filefifo/pkg/usr/bin/filefifo"
mkfifo "$stage/filefifo/pkg/usr/bin/filefifo-trigger"
printf '%s\n' 'user fbaduser 665 fbadgroup /var/lib/fbad /sbin/nologin' 'group fbadgroup 665' 'file /usr/bin/filefifo-trigger 0622 fbaduser fbadgroup' > "$stage/filefifo/pkg/usr/share/saphira/accounts.d/filefifo"
write_manifest filefifo '{"arch":"x86_64","build_time":18,"license":"MIT","name":"filefifo","origin":"filefifo","outputs":[{"dependencies":[],"description":"filefifo","name":"filefifo","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg filefifo > "$test_root/filefifo.log" 2>&1; then
	printf '%s\n' 'fifo file target unexpectedly packaged' >&2
	exit 1
fi
grep 'cannot ship in APKs' "$test_root/filefifo.log" >/dev/null
printf '%s\n' 'account file stanza refusal: ok (shape, payload binding, numeric refs, fifo refusal)'

# Legacy sidecars: recognised history ships beside its fragment,
# validated (names declared, past disjoint from present), recorded
# in the receipt. A foreign sidecar is stray; a lone sidecar (no
# fragment) is incoherent; malformed/reserved/undeclared entries
# fail the build.
mkdir -p "$stage/legacysvc/pkg/usr/bin" "$stage/legacysvc/pkg/usr/share/saphira/accounts.d"
printf '%s\n' legacysvc > "$stage/legacysvc/pkg/usr/bin/legacysvc"
printf '%s\n' 'user leguser 664 leggroup /var/lib/legacy /sbin/nologin' 'group leggroup 664' > "$stage/legacysvc/pkg/usr/share/saphira/accounts.d/legacysvc"
printf '%s\n' '# upstream 900 block' 'legacy user leguser 900 900' 'legacy group leggroup 900' > "$stage/legacysvc/pkg/usr/share/saphira/accounts.d/legacysvc.legacy"
write_manifest legacysvc '{"arch":"x86_64","build_time":19,"license":"MIT","name":"legacysvc","origin":"legacysvc","outputs":[{"dependencies":[],"description":"legacysvc","name":"legacysvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
run_makepkg legacysvc
python3 - "$stage/legacysvc/artifact-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
legacy = receipt["artifacts"][0]["accounts"]["legacy"]
assert legacy == {"users": [{"name": "leguser", "uid": "900", "gid": "900"}], "groups": [{"name": "leggroup", "gid": "900"}]}, legacy
PY
printf '%s\n' 'account legacy sidecar round-trip: ok (validated, receipt)'
# Physical presence: the sidecar must be a real file in the APK
# payload, not merely receipt metadata (systemd r6 shipped the
# fragment but not the sidecar - receipts knew, payload did not).
apk adbdump "$artifacts/x86_64/legacysvc-1-r0.apk" | grep -q 'name: legacysvc$' || {
	printf '%s\n' 'fragment missing from APK payload' >&2
	exit 1
}
apk adbdump "$artifacts/x86_64/legacysvc-1-r0.apk" | grep -q 'name: legacysvc.legacy$' || {
	printf '%s\n' 'sidecar missing from APK payload' >&2
	exit 1
}
printf '%s\n' 'account sidecar payload presence: ok (fragment + legacy in APK)'
legacybad()
{
	name=$1
	sidecar=$2
	message=$3
	extra=${4:-}
	mkdir -p "$stage/$name/pkg/usr/bin" "$stage/$name/pkg/usr/share/saphira/accounts.d"
	printf '%s\n' "$name" > "$stage/$name/pkg/usr/bin/$name"
	if [ -n "$extra" ]; then
		printf '%s\n' 'user legbaduser 665 legbadgroup /var/lib/legbad /sbin/nologin' 'group legbadgroup 665' > "$stage/$name/pkg/usr/share/saphira/accounts.d/$name"
	fi
	printf '%s\n' "$sidecar" > "$stage/$name/pkg/usr/share/saphira/accounts.d/$name.legacy"
	write_manifest "$name" '{"arch":"x86_64","build_time":20,"license":"MIT","name":"'"$name"'","origin":"'"$name"'","outputs":[{"dependencies":[],"description":"'"$name"'","name":"'"$name"'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
	if run_makepkg "$name" > "$test_root/$name.log" 2>&1; then
		printf '%s\n' "legacy sidecar $name unexpectedly packaged" >&2
		exit 1
	fi
	grep "$message" "$test_root/$name.log" >/dev/null
}
legacybad legacybadfrag 'frobnicate leguser' 'malformed stanza' yes
legacybad legacyundeclared 'legacy user ghostuser 900 900' 'not declared in the same fragment' yes
legacybad legacysame 'legacy user legbaduser 665 665' 'identical to the declared present' yes
legacybad legacyreserved 'legacy user root 0 0' 'can never be legacy' yes
legacybad legacylone 'legacy user ghostuser 900 900' 'not declared in the same fragment'
mkdir -p "$stage/legacystray/pkg/usr/bin" "$stage/legacystray/pkg/usr/share/saphira/accounts.d"
printf '%s\n' legacystray > "$stage/legacystray/pkg/usr/bin/legacystray"
printf '%s\n' 'user legbaduser 665 legbadgroup /var/lib/legbad /sbin/nologin' 'group legbadgroup 665' > "$stage/legacystray/pkg/usr/share/saphira/accounts.d/legacystray"
printf '%s\n' 'legacy user legbaduser 900 900' > "$stage/legacystray/pkg/usr/share/saphira/accounts.d/someoneelse.legacy"
write_manifest legacystray '{"arch":"x86_64","build_time":20,"license":"MIT","name":"legacystray","origin":"legacystray","outputs":[{"dependencies":[],"description":"legacystray","name":"legacystray","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}'
if run_makepkg legacystray > "$test_root/legacystray.log" 2>&1; then
	printf '%s\n' 'foreign sidecar unexpectedly packaged' >&2
	exit 1
fi
grep 'foreign account fragments' "$test_root/legacystray.log" >/dev/null
printf '%s\n' 'account legacy sidecar refusal: ok (malformed, undeclared, identical, reserved, lone, stray)'
