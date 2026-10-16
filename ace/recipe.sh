#!/bin/sh
pkgname=ace
pkgver=8.0.8
# r2: -dev must also carry ace/*.cpp: template implementation files that
# core headers #include directly (Intrusive_List etc.). Without them no
# consumer (Intel LMS) compiles.
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='ADAPTIVE Communication Environment core library (Intel LMS dependency)'
license='DOC'
origin=ace
repo=saphira
url=https://www.dre.vanderbilt.edu/~schmidt/ACE.html
# Vanderbilt ACE-only micro release (no TAO/CIAO/DAnCE sources in this
# archive - verified: only metadata mentions remain). NOTE on fetching:
# upstream TLS certificate expired 2026-09-25, so fetch-vendor-sources
# (TLS-only, correctly) cannot re-download this URL until Vanderbilt
# renews. Integrity is proven instead: all 1972 files under
# ACE_wrappers/ace/ and ACEXML/ are byte-identical to the same paths in
# the GitHub ACE+TAO-8.0.8 release bundle fetched over valid TLS;
# the vendored file plus this sidecar satisfy the --check gate.
source=https://download.dre.vanderbilt.edu/previous_versions/ACE-8.0.8.tar.gz
sha256=e12b98710eac9c5202de0f3d1e019eeae484e33eb90c0090e9929b92896b28c8

# Scope guardrail: only the ACE core library (libACE) is built and
# shipped. LMS links ACE::ACE for Reactor/Task/Thread/logging only;
# no TAO/CORBA, CIAO, DAnCE, ACEXML, ASNMP, Kokyu, apps, tests or
# examples are built or shipped. C++ consumers need gcc-libs at
# runtime (never the full compiler).
depends="gcc-libs"
# GNUmakefiles ship pre-generated: no MPC/perl run needed.
makedepends="binutils gcc make"
subpackages="$pkgname-dev"

recipe_build() {
	ACE_BALL="$RECIPE_DIR/files/ACE-${pkgver}.tar.gz"
	echo "$sha256  $ACE_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$ACE_BALL"
	# Traditional GNU configuration. (The worker flattens the tarball's
	# single ACE_wrappers/ top dir into $SRC, so paths are $SRC/ace.)
	printf '#include "ace/config-linux.h"\n' > "$SRC/ace/config.h"
	printf 'include $(ACE_ROOT)/include/makeinclude/platform_linux.GNU\n' > \
		"$SRC/include/makeinclude/platform_macros.GNU"
	export ACE_ROOT="$SRC"
	make -C "$ACE_ROOT/ace" -j${JOBS:-$(nproc)} ACE
}

recipe_install() {
	export ACE_ROOT="$SRC"
	# Upstream has no make-install for the traditional build; install
	# the documented set: shared library, full header tree, pkgconfig.
	install -d "$PKGDEST/usr/lib" "$PKGDEST/usr/include/ace" \
		"$PKGDEST/usr/lib/pkgconfig"
	# The real library is built in place under ace/; $ACE_ROOT/lib holds
	# only build-tree-relative symlinks (add_rel_link.sh), so install
	# the real file and create clean soname/dev links instead of
	# copying dangling links.
	install -m 0755 "$ACE_ROOT/ace/libACE.so.${pkgver}" \
		"$PKGDEST/usr/lib/libACE.so.${pkgver}"
	ln -sf "libACE.so.${pkgver}" "$PKGDEST/usr/lib/libACE.so"
	# ACE template implementations live in .cpp files #included by the
	# headers themselves - all three suffixes are -dev content.
	(cd "$ACE_ROOT/ace" && find . \( -name '*.h' -o -name '*.inl' -o -name '*.cpp' \) | \
		while IFS= read -r h; do
			install -D -m 0644 "$ACE_ROOT/ace/$h" "$PKGDEST/usr/include/ace/$h"
		done)
	sed -e "s|@prefix@|/usr|g" -e "s|@exec_prefix@|/usr|g" \
		-e "s|@libdir@|/usr/lib|g" -e "s|@includedir@|/usr/include|g" \
		-e "s|@VERSION@|${pkgver}|g" -e "s|@LIBS@||g" \
		"$ACE_ROOT/ace/ACE.pc.in" > "$PKGDEST/usr/lib/pkgconfig/ACE.pc"
	# No static archives: shared-only per Saphira policy.
	find "$PKGDEST" -name '*.a' -delete
}
