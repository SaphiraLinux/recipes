#!/bin/sh
# Saphira recipe: universal-ctags
#
# Universal Ctags: the maintained ctags implementation (exuberant-ctags
# lineage, https://github.com/universal-ctags/ctags), plus the readtags
# tag-file lookup client. Git-archive release tarball: no prebuilt
# configure, so autogen.sh runs at build time (autoconf/automake/libtool
# are build deps, not decoration).
#
# JSON output, seccomp sandboxing, YAML and PCRE2 regex support are
# enabled explicitly so a missing optional library fails the build
# instead of silently producing a quieter binary. libxml2 XPath rides
# on auto-detection and is asserted in the self-check below.

pkgname=universal-ctags
pkgver=6.2.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Maintained ctags implementation and readtags lookup client'
license='GPL-2.0-or-later'
origin=universal-ctags
repo=saphira
url=https://ctags.io/
vendor=https://github.com/universal-ctags/ctags/archive/refs/tags/v6.2.1.tar.gz
sha256=f56829e9a576025e98955597ee967099a871987b3476fbd8dbbc2b9dc921f824
# Runtime closure is proven by the linkage gate in recipe_build (exact
# NEEDED set on both installed binaries): ctags links jansson statically
# and readtags does not use it at all, so no libjansson.so is needed at
# runtime. jansson-dev stays a build dep. Set from the first verified build.
depends="libseccomp libxml2 libyaml pcre2"
makedepends="
	autoconf
	automake
	binutils
	gcc
	jansson-dev
	libtool
	libseccomp-dev
	libxml2-dev
	libyaml-dev
	make
	pcre2-dev
	pkgconf
	python-docutils
"
subpackages="$pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/ctags-6.2.1.tar.gz"
	cd "$SRC"
	echo "$sha256  $RECIPE_DIR/files/ctags-6.2.1.tar.gz" | sha256sum -c -
	# PackCC emits `int i` plus a counting loop for every unbounded
	# repetition, but the counter is only read when it bounds the loop
	# or enforces a minimum. In zero-or-more repetitions it is
	# set-but-never-read: 593 -Wunused-but-set-variable warnings across
	# the PEG parsers. Fixed in the generator (counter only when read),
	# not hidden with -Wno-*. Applies cleanly or fails loudly; fuzz or
	# offsets mean the template moved and the patch must be rebased.
	patch -Np1 -i "$RECIPE_DIR/files/packcc-unbounded-loop-no-unused-counter.patch" >"$BUILDDIR/packcc-counter.log" 2>&1 || {
		echo "ERROR: packcc counter patch failed to apply" >&2
		cat "$BUILDDIR/packcc-counter.log" >&2
		return 1
	}
	if grep -qE 'fuzz|offset|suspicious' "$BUILDDIR/packcc-counter.log"; then
		echo "ERROR: packcc counter patch applied loosely (fuzz/offset): rebase it, do not ship it" >&2
		cat "$BUILDDIR/packcc-counter.log" >&2
		return 1
	fi
	./autogen.sh >>"$BUILDDIR/autogen.log" 2>&1
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=-march=x86-64-v3 ;;
		aarch64) march=-march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for universal-ctags: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--enable-json --enable-seccomp --enable-yaml --enable-pcre2 \
		CC=gcc "CFLAGS=-Os $march"
	make -j${JOBS:-$(nproc)}
	# Feature gates: the capabilities Stage 2 (sysref ctags tool) and
	# the task statement require, proven on the built binaries.
	# Upstream names the seccomp feature "sandbox" in --list-features.
	./ctags --list-features >"$BUILDDIR/features.txt"
	grep -qw json "$BUILDDIR/features.txt" || { echo "ERROR: json support missing" >&2; return 1; }
	grep -qw sandbox "$BUILDDIR/features.txt" || { echo "ERROR: seccomp (sandbox) support missing" >&2; return 1; }
	grep -qw yaml "$BUILDDIR/features.txt" || { echo "ERROR: yaml support missing" >&2; return 1; }
	grep -qw pcre2 "$BUILDDIR/features.txt" || { echo "ERROR: pcre2 support missing" >&2; return 1; }
	grep -qw xpath "$BUILDDIR/features.txt" || { echo "ERROR: xml/xpath support missing" >&2; return 1; }
	./ctags --list-output-formats | grep -q json || { echo "ERROR: json output format missing" >&2; return 1; }
	# Functional gate: index C covering functions, typedefs, structs,
	# enums and macros; prove JSON output and readtags lookup.
	mkdir -p "$BUILDDIR/gate"
	cat >"$BUILDDIR/gate/sample.c" <<'EOF'
typedef unsigned long widget_flags_t;
enum widget_colour { WIDGET_RED, WIDGET_BLUE };
struct widget_state { int fd; widget_flags_t flags; };
#define WIDGET_CLAMP(x) ((x) < 0 ? 0 : (x))
int widget_open(int fd, int flags);
int widget_open(int fd, int flags) { return fd + flags; }
EOF
	# Upstream spells the tag-file option short-only (-o); there is no
	# --output long form (options.c, ctags.1.rst.in). Spelling it long
	# fails the build with "Unknown option: --output".
	# JSON output AND classic output are proven separately: readtags only
	# reads the classic tab-separated format, so the JSON tags file it
	# cannot consume gets its own assertions while readtags checks a
	# classic file. (One file for both tools fails silently: readtags
	# finds nothing in JSON and the old || return 1 said nothing.)
	./ctags --output-format=json -o "$BUILDDIR/gate/tags.json" "$BUILDDIR/gate/sample.c" || return 1
	# Jansson dumps compact JSON (no space after the colon), so allow
	# optional whitespace rather than asserting one exact rendering.
	# Loud on failure: a bare "|| return 1" here once hid behind a
	# passing make with no error text in the log.
	for sym in widget_open WIDGET_CLAMP widget_state WIDGET_RED widget_flags_t; do
		grep -q "\"name\": *\"$sym\"" "$BUILDDIR/gate/tags.json" || {
			echo "ERROR: $sym missing from JSON tags output:" >&2
			cat "$BUILDDIR/gate/tags.json" >&2
			return 1
		}
	done
	./ctags -o "$BUILDDIR/gate/tags" "$BUILDDIR/gate/sample.c" || return 1
	./readtags -t "$BUILDDIR/gate/tags" widget_open >"$BUILDDIR/gate/lookup.txt" || {
		echo "ERROR: readtags lookup failed" >&2
		return 1
	}
	grep -q widget_open "$BUILDDIR/gate/lookup.txt" || {
		echo "ERROR: widget_open missing from readtags lookup" >&2
		cat "$BUILDDIR/gate/lookup.txt" >&2
		return 1
	}
	# Linkage gate: the runtime closure declared in depends= must be
	# exactly what the binaries need. Static jansson leaves no DT_NEEDED
	# trace and a stripped binary has no symtab to grep, so the closure
	# is asserted as an exact NEEDED set (libc is the implicit base)
	# while the json capability stays proven functionally above.
	# Anything unexpected fails here so the recipe author fixes depends=
	# instead of shipping a broken or bloated closure.
	echo "--- NEEDED ctags:"; readelf -d ./ctags | grep NEEDED
	echo "--- NEEDED readtags:"; readelf -d ./readtags | grep NEEDED
	for lib in "libxml2.so" "libyaml-0.so.2" "libseccomp.so.2" "libpcre2-8.so.0"; do
		readelf -d ./ctags | grep -q "\[$lib" || { echo "ERROR: NEEDED $lib missing from ctags" >&2; return 1; }
	done
	nneed=$(readelf -d ./ctags | grep -c '(NEEDED)') || nneed=0
	rneed=$(readelf -d ./readtags | grep -c '(NEEDED)') || rneed=0
	[ "$nneed" = 5 ] || { echo "ERROR: unexpected ctags closure ($nneed NEEDED entries):" >&2; readelf -d ./ctags | grep NEEDED >&2; return 1; }
	[ "$rneed" = 1 ] || { echo "ERROR: unexpected readtags closure ($rneed NEEDED entries):" >&2; readelf -d ./readtags | grep NEEDED >&2; return 1; }
	echo "gates: features, formats, C index, JSON output, readtags lookup ok"
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
