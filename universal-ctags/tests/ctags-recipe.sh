#!/bin/sh
# universal-ctags recipe checks: vendored source verifies, pins match the
# recipe, build tooling and feature assertions are present, and no
# install-time execution happens at recipe level.

set -eu

root=$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)
files=$root/files

fail=0
check() {
	if [ "$1" = 0 ]; then
		printf '  ok   %s\n' "$2"
	else
		printf '  FAIL %s\n' "$2"
		fail=1
	fi
}

[ -f "$files/ctags-6.2.1.tar.gz" ]
check $? "vendored ctags archive present"

(cd "$files" && echo "$(cat ctags-6.2.1.tar.gz.sha256)" | sha256sum -c - >/dev/null)
check $? "vendored archive verifies against sidecar"

grep -q '^vendor=https://github.com/universal-ctags/ctags/archive/refs/tags/v6.2.1.tar.gz$' "$root/recipe.sh"
check $? "recipe vendor URL matches archived basename"

grep -q '^sha256=f56829e9a576025e98955597ee967099a871987b3476fbd8dbbc2b9dc921f824$' "$root/recipe.sh"
check $? "recipe sha256 pin matches sidecar (bare sha256= pairs with vendor=)"

grep -qF -- '--enable-json' "$root/recipe.sh"
check $? "json support explicitly enabled (fail-closed)"

grep -qF -- '--enable-seccomp' "$root/recipe.sh"
check $? "seccomp support explicitly enabled (fail-closed)"

grep -q 'jansson-dev' "$root/recipe.sh"
check $? "json build dependency declared"

grep -q 'sandbox' "$root/recipe.sh"
check $? "build asserts upstream sandbox (seccomp) feature name"

grep -q 'readtags' "$root/recipe.sh"
check $? "build asserts readtags lookup"

grep -q 'readelf' "$root/recipe.sh"
check $? "build asserts linkage closure"

grep -qF -- '-o "$BUILDDIR/gate/tags"' "$root/recipe.sh"
check $? "gate writes tags with upstream short -o spelling"

! grep -qF -- '--output=' "$root/recipe.sh"
check $? "no invented --output long option (upstream is short-only)"

grep -qF -- '\"name\": *' "$root/recipe.sh"
check $? "gate tolerates compact jansson JSON spacing"

grep -q 'missing from JSON tags output' "$root/recipe.sh"
check $? "gate failure names the missing symbol"

grep -qF -- '-t "$BUILDDIR/gate/tags"' "$root/recipe.sh"
check $? "readtags checks the classic tags file"

! grep -qF -- '-t "$BUILDDIR/gate/tags.json"' "$root/recipe.sh"
check $? "readtags never fed JSON it cannot parse"

[ -f "$files/packcc-unbounded-loop-no-unused-counter.patch" ]
check $? "packcc counter patch vendored"

grep -qF -- 'packcc-unbounded-loop-no-unused-counter.patch' "$root/recipe.sh"
check $? "build applies the packcc counter patch"

grep -q 'for (;;)' "$files/packcc-unbounded-loop-no-unused-counter.patch"
check $? "patch emits a counter-less loop for unread counters"

grep -q '^depends="libseccomp libxml2 libyaml pcre2"$' "$root/recipe.sh"
check $? "runtime closure drops libjansson.so (static in ctags, unused by readtags)"

grep -q 'unexpected ctags closure' "$root/recipe.sh"
check $? "linkage gate asserts the exact NEEDED set"

grep -q 'unexpected readtags closure' "$root/recipe.sh"
check $? "readtags closure asserted too"

exit $fail
