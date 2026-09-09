#!/bin/sh

# Tuned dynamic system-tuning daemon. Python daemons need their
# imported modules as real dependencies: dbus (service bus) and
# pygobject (GLib mainloop integration) are hard imports on the
# daemon path, so they ride along. Shelled-out helpers (dmidecode,
# ethtool and friends) degrade gracefully when absent and stay out.
# No service units this round (documented follow-up, same as FRR).

pkgname=tuned
pkgver=2.28.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Dynamic system tuning daemon"
license="GPL-2.0-or-later"
origin=tuned
repo=saphira
url=https://github.com/redhat-performance/tuned
source=https://github.com/redhat-performance/tuned/archive/refs/tags/v2.28.0.tar.gz
sha256=e8fa0a3493dec60462a36082c9755c1f38ace89640dea816b0833d48d5df686b

depends="
    python3
    python-dbus
    pygobject
"

makedepends="
    python3
"

recipe_build()
{
	:
}

recipe_install()
{
	make DESTDIR="$PKGDEST" PREFIX=/usr install
}
