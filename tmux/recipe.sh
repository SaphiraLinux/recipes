#!/bin/sh

pkgname=tmux
pkgver=3.7b
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Terminal multiplexer'
license='ISC'
origin=tmux
repo=saphira
url=https://tmux.github.io/
source=https://github.com/tmux/tmux/releases/download/${pkgver}/tmux-${pkgver}.tar.gz
sha256=87f2e99e3b685973f2ca002ffd6ed7e51a5744f7009daae5a15670b6d532db96

depends="libevent ncurses"
makedepends="gcc make pkgconf bison libevent-dev ncurses-dev"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	# bison ships --disable-yacc (proven v0 decision), but tmux's configure
	# hard-requires a literal `yacc`. Recipe-scoped shim: bison -y in PATH.
	mkdir -p "$BUILDDIR/shims"
	printf '#!/bin/sh\nexec bison -y "$@"\n' > "$BUILDDIR/shims/yacc"
	chmod +x "$BUILDDIR/shims/yacc"
	PATH="$BUILDDIR/shims:$PATH" ./configure --prefix=/usr --enable-sixel
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
