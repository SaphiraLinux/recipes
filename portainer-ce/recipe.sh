#!/bin/sh

pkgname=portainer-ce
pkgver=2.45.2
pkgrel=2
# r2: ship the upstream CE licence notice (2026-10-23). license=
# stays BUSL-1.1 for Saphira's own unit files (Saphira-owned-service
# policy, same wrapper reasoning as firmware-tools r2): it never
# covered Portainer's software, and the referenced CE image is
# zlib-licensed upstream (LICENCE text vendored as
# files/LICENSE.Portainer-CE). No silent relicense in either
# direction; Portainer BE is a different product, not referenced.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Portainer Community Edition service units (pinned image, loopback only)'
license='BUSL-1.1'
origin=portainer-ce
repo=saphira
url=https://www.portainer.io/
# r1: service package, no compiled code. Runs the pinned upstream image
# portainer/portainer-ce:2.45.2 (2.45 LTS line, 2026-10-08) as a host
# service on Docker hosts. Deliberate decisions:
#   - 127.0.0.1:9443 only (Portainer's own TLS on 9443; remote access
#     rides an SSH tunnel, never a public port);
#   - named volume portainer_data (survives container replacement and
#     package removal; never pruned by install/upgrade/remove);
#   - dual init (systemd unit + OpenRC init.d, both disabled by
#     default like every Saphira daemon package);
#   - first-run admin password is set in the Portainer UI over the
#     loopback address (or tunnel); no credentials in this package.
# Removal stops the container and disables the service; the volume, the
# image and every managed workload/container/image stay untouched.

depends="docker-engine docker-cli"
makedepends=""

recipe_build()
{
	sh -n "$RECIPE_DIR/files/portainer-ce.initd" ||
		{ echo "ERROR: initd syntax check failed" >&2; return 1; }
	grep -q 'portainer/portainer-ce:2.45.2' "$RECIPE_DIR/files/portainer-ce.service" ||
		{ echo "ERROR: service image pin missing" >&2; return 1; }
	grep -q 'portainer/portainer-ce:2.45.2' "$RECIPE_DIR/files/portainer-ce.initd" ||
		{ echo "ERROR: initd image pin missing" >&2; return 1; }
	if grep -qE '\-p [0-9]+:9443' "$RECIPE_DIR"/files/portainer-ce.service "$RECIPE_DIR"/files/portainer-ce.initd; then
		echo "ERROR: Portainer bound beyond loopback" >&2; return 1
	fi
	grep -q 'portainer_data:/data' "$RECIPE_DIR/files/portainer-ce.service" ||
		{ echo "ERROR: data volume missing" >&2; return 1; }
	mkdir -p "$BUILDDIR"
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/portainer-ce.initd" \
		"$PKGDEST/etc/init.d/portainer-ce"
	install -D -m 0644 "$RECIPE_DIR/files/portainer-ce.service" \
		"$PKGDEST/usr/lib/systemd/system/portainer-ce.service"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE.Portainer-CE" \
		"$PKGDEST/usr/share/licenses/portainer-ce/LICENSE.Portainer-CE"
}
