#!/bin/sh

pkgname=elixir
pkgver=1.20.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Elixir language (RabbitMQ CLI toolchain)"
license='Apache-2.0'
origin=elixir
repo=saphira
url=https://elixir-lang.org/
source=https://github.com/elixir-lang/elixir/archive/refs/tags/v1.20.4.tar.gz
sha256=2f87be1702583ecbeee82c0ad4d6353de96463cfa0fa6e7557e05f68d90da869

depends="
    erlang
"

makedepends="
    binutils
    gcc
    make
    erlang
"

# Elixir bootstraps from Erlang alone (make runs
# `erl -s elixir_compiler bootstrap`); no prior Elixir needed.
recipe_build()
{
	cd "$SRC" && make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" PREFIX=/usr install
	for p in \
		usr/bin/elixir \
		usr/bin/elixirc \
		usr/bin/iex \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: elixir payload is missing $p" >&2
			return 1
		}
	done
}
