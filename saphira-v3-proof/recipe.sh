#!/bin/sh

pkgname=saphira-v3-proof
pkgver=1.0.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira Genesis x86-64-v3 validation proof: AVX2/FMA/BMI2/F16C/LZCNT + pthreads benchmark/stress test'
license='BUSL-1.1'
origin=saphira-v3-proof
repo=saphira
url=https://saphira.vm2.uk/

# Vendored validation source (no upstream download; byte-pinned below).
# The proof is inherently x86-64-v3: it #errors without -march=x86-64-v3,
# so this recipe is arch-specific by design.
proof_sha256='40f6bfd8958e370013793eea5fe211e7b5b7a27e0aa131e37099b1aec03e84cc'

depends=""
makedepends="
	gcc
	make
"

recipe_build()
{
	echo "$proof_sha256  $SRC/files/saphira-v3-proof.c" | sha256sum -c -
	install -m 0644 "$SRC/files/saphira-v3-proof.c" "$SRC/saphira-v3-proof.c"
	install -m 0644 "$SRC/files/Makefile" "$SRC/Makefile"
	install -m 0644 "$SRC/files/README.md" "$SRC/README.md"
	make -C "$SRC" -j${JOBS:-$(nproc)}
	# The staged proof must pass on the build host: this is the point of
	# the package (compiler + libc + pthreads + x86-64-v3 execution).
	"$SRC/saphira-v3-proof" | grep -q 'RESULT           : PASS'
}

recipe_install()
{
	make -C "$SRC" install DESTDIR="$PKGDEST" PREFIX=/usr
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-v3-proof/LICENSE"
}
