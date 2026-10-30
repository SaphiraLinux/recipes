#!/bin/sh

# bash-completion: programmable shell completions data
# (libvirt -Dbash_completion).

pkgname=bash-completion
pkgver=2.18.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Programmable bash completion data"
license="GPL-2.0-or-later"
origin=bash-completion
repo=saphira
url=https://github.com/scop/bash-completion
source=https://github.com/scop/bash-completion/releases/download/${pkgver}/bash-completion-${pkgver}.tar.xz
sha256=88bcf85124f77f74f2f2f8bcd16ac4382d807a827ede742a64940c7116aea33f

# Data-only package: shell completions, no compiled code.
makedepends="
    make
"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/bash-completion/COPYING"
	for p in usr/share/bash-completion/bash_completion; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: bash-completion payload is missing $p" >&2
			return 1
		}
	done
}
