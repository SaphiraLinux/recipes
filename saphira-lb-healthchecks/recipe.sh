#!/bin/sh

pkgname=saphira-lb-healthchecks
pkgver=2026.09
pkgrel=1
pkgarch=noarch
pkgdesc='Saphira generic external LB healthcheck library (ldirectord/HAProxy checks under /var/lib/lb/saphira)'
license=MIT
origin=saphira-lb-healthchecks
repo=saphira
url=https://saphira.vm2.uk/

# Payload is authored in files/ (clean-room, MIT); no upstream source.
# depends pulls the full Saphira loadbalancing stack so that
# `apk add saphira-lb-healthchecks` installs working LB services:
# ipvsadm (LVS), ldirectord (resource-agents), haproxy.
depends="
	bash
	coreutils
	curl
	haproxy
	iputils
	ipvsadm
	openssl
	python3
	resource-agents
"
makedepends=""

recipe_build()
{
	# Syntax validation of every delivered artifact (authoring gate;
	# functional clean-root validation happens where a test target exists).
	# PYTHONPYCACHEPREFIX keeps py_compile from writing __pycache__ into
	# the recipe dir, which is bound read-only in the build namespace.
	local f
	for f in "$RECIPE_DIR"/files/lb.saphira.*; do
		sh -n "$f" || return 1
	done
	sh -n "$RECIPE_DIR/files/lib/lb-saphira-common.sh" || return 1
	PYTHONPYCACHEPREFIX="$BUILDDIR/pycache" python3 -m py_compile \
		"$RECIPE_DIR/files/saphira-lb-probe" || return 1
	# Invoke via python3: the build must not depend on the exec bit
	# surviving the read-only /recipes bind.
	PYTHONPYCACHEPREFIX="$BUILDDIR/pycache" python3 \
		"$RECIPE_DIR/files/saphira-lb-probe" --help >/dev/null || return 1
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/var/lib/lb/saphira"
	for f in "$RECIPE_DIR"/files/lb.saphira.*; do
		install -m 0755 "$f" "$PKGDEST/var/lib/lb/saphira/$(basename "$f")"
	done
	install -D -m 0755 "$RECIPE_DIR/files/saphira-lb-probe" \
		"$PKGDEST/usr/bin/saphira-lb-probe"
	install -D -m 0644 "$RECIPE_DIR/files/lib/lb-saphira-common.sh" \
		"$PKGDEST/usr/share/saphira/lb-healthchecks/lib/lb-saphira-common.sh"
	install -D -m 0644 "$RECIPE_DIR/files/README.md" \
		"$PKGDEST/usr/share/doc/saphira-lb-healthchecks/README.md"
	find "$PKGDEST" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
}
