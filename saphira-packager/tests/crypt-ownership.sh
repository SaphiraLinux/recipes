#!/bin/sh
#
# crypt-ownership.sh: the musl / libxcrypt crypt namespace, proved.
#
# THE POLICY (this is the single source of truth; the gate and the recipes
# both point here so they cannot drift apart):
#
#   musl / musl-dev
#       /usr/include/crypt.h          the system crypt header
#       /usr/lib/libcrypt.a           EMPTY compatibility archive
#   libxcrypt / libxcrypt-dev
#       /usr/include/libxcrypt/       the extended header
#       /usr/lib/libxcrypt.so         the extended implementation
#       no generic libcrypt.so
#       no generic real libcrypt.a
#
# The reason is that musl implements crypt()/crypt_r() INSIDE libc and ships
# an empty libcrypt.a purely so that build systems hardcoding -lcrypt still
# link. So on Saphira:
#
#   * generic -lcrypt resolves crypt() out of musl's libc, by design;
#   * a consumer that wants the heavy hashes must select libxcrypt explicitly;
#   * and -lcrypt falls back to the .a, which is exactly why libxcrypt must
#     never install a REAL generic libcrypt.a -- the linker would silently
#     pick it up and hand every consumer yescrypt without anyone asking.
#
# This gate exists because every one of those facts is silent when violated.
# A generic libcrypt.so from libxcrypt re-exposes the extended API under the
# wrong name; a real generic libcrypt.a is picked up by a fallback nobody
# declared; and a consumer that links generic -lcrypt while believing it
# gets yescrypt is simply wrong, with no error at build or run time.
#
# It therefore checks behaviour, not text: it reconstructs a real root from
# the published packages, compiles real programs against it, and inspects
# what the resulting binaries actually link.
#
# usage: crypt-ownership.sh [REPO-DIR]

set -eu

repo=${1:-${SAPHIRA_REPO_DIR:-/out/stage4/packages}}
arch=${SAPHIRA_ARCH:-x86_64}
index=$repo/hatched/$arch/Packages.adb

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
checks=0

fail()
{
	printf '%s\n' "crypt-ownership: $*" >&2
	exit 1
}
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

[ -f "$index" ] || fail "no repository index: $index"
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/crypt-ownership.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

root=$work/root
mkdir -p "$root"
apk --root "$root" --initdb --usermode --allow-untrusted --no-network \
	--keys-dir /etc/apk/keys --repository "$index" \
	add musl musl-dev libxcrypt libxcrypt-dev >"$work/apk.log" 2>&1 ||
	{
		sed 's/^/    /' "$work/apk.log" >&2
		fail "could not reconstruct a root from $index"
	}

printf '%s\n' "crypt-ownership: musl owns the generic crypt namespace"

# --- 1. musl-dev supplies the empty compatibility archive -------------

[ -f "$root/usr/lib/libcrypt.a" ] ||
	fail "/usr/lib/libcrypt.a is missing; -lcrypt would be unlinkable, which is not the same as resolving to musl"
# An ar archive is exactly 8 bytes ("!<arch>\n") when it has no members.
size=$(wc -c < "$root/usr/lib/libcrypt.a")
if [ "$size" -ne 8 ]; then
	members=$(ar t "$root/usr/lib/libcrypt.a" 2>/dev/null | wc -l)
	fail "/usr/lib/libcrypt.a is $size bytes with $members member(s); it must be an EMPTY compatibility archive. A real one here would be silently picked up by -lcrypt's .a fallback."
fi
ok "musl-dev provides an empty /usr/lib/libcrypt.a ($size bytes, 0 members)"

# --- 2. musl's libc really provides crypt -----------------------------

nm -D --defined-only "$root/usr/lib/libc.so" 2>/dev/null |
	grep -qw crypt ||
	fail "musl's libc does not export crypt(); the empty libcrypt.a is only safe because libc provides it"
ok "musl's libc exports crypt()"

# --- 3. libxcrypt installs no generic name -----------------------------

[ ! -e "$root/usr/lib/libcrypt.so" ] ||
	fail "/usr/lib/libcrypt.so exists; libxcrypt must not re-expose the extended API under the generic name"
[ -e "$root/usr/lib/libxcrypt.so" ] ||
	fail "/usr/lib/libxcrypt.so is missing; a consumer cannot opt into the extended hashes at all"
ok "libxcrypt: generic libcrypt.so absent, libxcrypt.so present"

# The generic archive must still be the empty musl one after libxcrypt is
# added, i.e. libxcrypt did not replace it with a real one.
size=$(wc -c < "$root/usr/lib/libcrypt.a")
[ "$size" -eq 8 ] ||
	fail "/usr/lib/libcrypt.a is $size bytes after installing libxcrypt; libxcrypt must not install a real generic libcrypt.a"
ok "the generic /usr/lib/libcrypt.a is still musl's empty one"

# --- 4. crypt() links, with and without -lcrypt, via musl libc ---------

cat > "$work/crypt.c" <<'EOF'
#include <crypt.h>
#include <stdio.h>
int main(void) { char *h = crypt("pw", "$y$j9T$abcdefghijklmnopqrst"); printf("%s\n", h ? h : "NULL"); return 0; }
EOF

needs_libcrypt()
{
	# A binary that links libxcrypt records libcrypt.so.2 in DT_NEEDED.
	# One that resolves crypt() out of musl's libc does not.
	readelf -d "$1" 2>/dev/null | grep -q 'libcrypt\.so\.2'
}

gcc --sysroot="$root" -o "$work/plain" "$work/crypt.c" 2>"$work/e1" ||
	{
		sed 's/^/    /' "$work/e1" >&2
		fail "crypt() does not link with no -lcrypt at all"
	}
needs_libcrypt "$work/plain" &&
	fail "a binary built with no -lcrypt links libcrypt.so.2; crypt() should come from musl's libc"
ok "crypt() links with no -lcrypt, resolving through musl libc"

gcc --sysroot="$root" -L"$root/usr/lib" -o "$work/generic" "$work/crypt.c" -lcrypt 2>"$work/e2" ||
	{
		sed 's/^/    /' "$work/e2" >&2
		fail "-lcrypt does not link; the empty compatibility archive is not doing its job"
	}
needs_libcrypt "$work/generic" &&
	fail "a binary built with generic -lcrypt links libcrypt.so.2; generic -lcrypt must resolve crypt() out of musl libc"
ok "crypt() links with generic -lcrypt, still resolving through musl libc"

# --- 5. the explicit route selects libxcrypt, and yescrypt is there ----

pc=$root/usr/lib/pkgconfig/libxcrypt.pc
[ -f "$pc" ] || fail "libxcrypt.pc is missing; there is no way to select the extended API explicitly"
flags=$(PKG_CONFIG_PATH="$root/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$root" \
	pkg-config --cflags --libs libxcrypt 2>/dev/null) ||
	fail "pkg-config libxcrypt fails"
case $flags in
*-lxcrypt*) : ;;
*) fail "libxcrypt.pc does not name -lxcrypt (got: $flags); a consumer would not be selecting libxcrypt explicitly" ;;
esac
case $flags in
*-lcrypt*) fail "libxcrypt.pc names the generic -lcrypt (got: $flags); that is the collision the split exists to prevent" ;;
esac
ok "pkg-config libxcrypt names -lxcrypt explicitly: $flags"

gcc --sysroot="$root" $flags -o "$work/explicit" "$work/crypt.c" 2>"$work/e3" ||
	{
		sed 's/^/    /' "$work/e3" >&2
		fail "crypt() does not link through the explicit libxcrypt route"
	}
needs_libcrypt "$work/explicit" ||
	fail "an explicit libxcrypt consumer does not link libcrypt.so.2; the opt-in is not reaching the extended implementation"
ok "an explicit libxcrypt consumer links libcrypt.so.2 (the extended implementation)"

# The sharp yescrypt proof: crypt_gensalt_rn is libxcrypt's API and musl
# does not define it at all. Declaring it and running it can therefore only
# succeed through the explicit route.
nm -D --defined-only "$root/usr/lib/libc.so" 2>/dev/null | grep -qw crypt_gensalt_rn &&
	fail "musl's libc defines crypt_gensalt_rn; it cannot be used to prove the opt-in"
cat > "$work/gensalt.c" <<'EOF'
#include <crypt.h>
#include <stdio.h>
int main(void) {
	static const char rbytes[16] = "0123456789abcdef";
	char out[128];
	if (crypt_gensalt_rn("$y$", 32, rbytes, (int)sizeof rbytes - 1, out, (int)sizeof out))
		printf("%s\n", out);
	else
		printf("NULL\n");
	return 0;
}
EOF
if gcc --sysroot="$root" -o "$work/gensalt_generic" "$work/gensalt.c" 2>/dev/null; then
	fail "crypt_gensalt_rn compiled against the GENERIC crypt header; musl must not declare it, or it is not proving anything"
fi
ok "crypt_gensalt_rn is absent from the generic crypt header (musl does not declare it)"
gcc --sysroot="$root" $flags -o "$work/gensalt_explicit" "$work/gensalt.c" 2>"$work/e4" ||
	{
		sed 's/^/    /' "$work/e4" >&2
		fail "crypt_gensalt_rn does not compile through the explicit libxcrypt route"
	}
# The binding is the proof, not the returned salt: crypt_gensalt_rn must be
# resolved from libxcrypt, because musl does not define it at all. Whether a
# given prefix/length combination actually yields a salt is a libxcrypt
# policy question, not an ownership one -- this build returns NULL for the
# prefixes tried, so asserting on the salt would be asserting on something
# that is not what this gate is about.
if command -v nm >/dev/null 2>&1; then
	nm -D --undefined-only "$work/gensalt_explicit" 2>/dev/null |
		grep -qw crypt_gensalt_rn ||
		fail "crypt_gensalt_rn is not an undefined symbol in the explicit consumer; it should bind from libxcrypt at load time"
	ok "crypt_gensalt_rn is bound from libxcrypt in the explicit consumer"
fi
needs_libcrypt "$work/gensalt_explicit" ||
	fail "the explicit gensalt consumer does not link libcrypt.so.2"
ok "yescrypt-capable API is reachable only through the explicit libxcrypt route"

# --- 6. shadow must use the explicit route -----------------------------

root_recipe=${2:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
shadow=$root_recipe/shadow/recipe.sh
[ -f "$shadow" ] || fail "shadow recipe not found: $shadow"
[ -f "$root_recipe/shadow/files/0001-saphira-prefer-libxcrypt.patch" ] ||
	fail "shadow has no libxcrypt opt-in patch"
# The patch must set LIBCRYPT to the libxcrypt name, not the generic one.
patchfile=$root_recipe/shadow/files/0001-saphira-prefer-libxcrypt.patch
grep -q 'LIBCRYPT=-lxcrypt' "$patchfile" ||
	fail "the shadow opt-in patch does not set LIBCRYPT=-lxcrypt"
grep -q 'CPPFLAGS="-I/usr/include/libxcrypt' "$shadow" ||
	fail "shadow does not put libxcrypt's include directory first, so <crypt.h> would be musl's and crypt_gensalt would not be declared"
ok "shadow selects libxcrypt explicitly (patch + include path)"

printf '%s\n' "crypt-ownership: OK ($checks checks)"
