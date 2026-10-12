# r13: move the control-plane identity off 132, which is qmail's and published;
# 132 avoided systemd's block but collided with qmail. 132 -> 151. Unpublished
# and disabled, so no migration and no legacy sidecar.
pkgname=saphira-router
pkgver=0.1.0
pkgrel=13
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira Linux multi-tenant control plane: load balancing, routing, virtual networking and managed nodes'
license='BUSL-1.1'
origin=saphira-router
repo=saphira
url=https://saphira.vm2.uk/

# Intentionally unpublished, NOT broken.
#
# Router is out of the normal build and publication set until the control
# plane and its package lifecycle are explicitly released for testing/public
# use. Both are still moving: the provider seam is new, and the uninstall
# behaviour (stale /run socket, service-account retention, /var/lib retention)
# is an open policy decision. Publishing a half-settled package lifecycle to
# consumers before that decision is made is the thing this flag prevents.
#
# disabled=yes is a publication gate, not a deletion. The recipe stays here,
# stays buildable and stays installable for lab work:
#
#   SAPHIRA_ALLOW_DISABLED=1 buildpkg saphira-router
#
# The override is scoped to the package named on the command line; a disabled
# recipe reached as a dependency still fails closed in resolvepkg. saphira-build
# scan reports and skips this recipe, so it is never queued automatically.
disabled=yes
disabled_reason='intentionally unpublished pending explicit release: the control plane and its package lifecycle are still changing; build and test it deliberately with SAPHIRA_ALLOW_DISABLED=1'

# The control plane drives other daemons over their documented surfaces; it
# does not link them. Nothing here is privileged, which is deliberate: the
# core runs unprivileged and grants capability at a drone boundary instead.
depends="
	sqlite
	libargon2
	ncurses
	json-c
	openssl
"
# The -dev packages are REQUIRED: the build seed provides musl/kernel
# headers but not library headers, so every library we compile against needs
# its dev package installed into the build root. Omitting them fails at the
# first #include with "No such file or directory", not with a dependency
# error -- which is exactly what the first build attempt did.
makedepends="
	gcc
	make
	sqlite-dev
	ncurses-dev
	json-c-dev
	openssl-dev
	libargon2-dev
"
subpackages="$pkgname-doc"

recipe_build()
{
	# Local source, built out of tree so files/ stays pristine (D1 9).
	rm -rf "$BUILDDIR/build"
	mkdir -p "$BUILDDIR/build"
	cp -r "$RECIPE_DIR/files/Makefile" "$RECIPE_DIR/files/src" \
		"$RECIPE_DIR/files/include" "$BUILDDIR/build/"
	mkdir -p "$BUILDDIR/build/modules"
	cp "$RECIPE_DIR"/files/modules/*.c "$BUILDDIR/build/modules/"

	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=x86-64-v3 ;;
		aarch64) march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac

	# The build tree carries no dev shim: argon2.h comes from the
	# libargon2-dev build dependency like any other packaged header.
	# BINDIR points objects and the binary at the same tree, so
	# recipe_install knows exactly where the binary is.
	# Build the `daemon` target only. `all` also builds the module fixtures,
	# including mod_badabi.so, which is a DELIBERATELY BROKEN module used to
	# keep the refusal path testable. It is a test artefact and has no business
	# in a production build, where it is compiled and then discarded.
	make -C "$BUILDDIR/build" -j"${JOBS:-$(nproc)}" daemon \
		CC=gcc ARCH="$march" PREFIX=/usr DEPS_INC="" BINDIR="$BUILDDIR/build"
}

recipe_install()
{
	# One binary with three roles: the daemon (sole writer), the CLI and the
	# TUI. The CLI and TUI are clients of the daemon's API and never open the
	# database themselves (D1 3.2, D4 1).
	install -D -m 0755 "$BUILDDIR/build/saphira-router" \
		"$PKGDEST/usr/bin/saphira-router"

	# Documentation.
	install -D -m 0644 "$RECIPE_DIR/files/man/saphira-router.1" \
		"$PKGDEST/usr/share/man/man1/saphira-router.1"
	install -d "$PKGDEST/usr/share/doc/saphira-router"
	for d in "$RECIPE_DIR"/files/docs/*.md; do
		install -m 0644 "$d" "$PKGDEST/usr/share/doc/saphira-router/"
	done

	# Dual init: BOTH definitions ship, NEITHER is enabled. Enabling is a
	# profile decision, not a recipe one (D1 9, D10 4).
	install -D -m 0755 "$RECIPE_DIR/files/saphira-router.initd" \
		"$PKGDEST/etc/init.d/saphira-router"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-router.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-router.service"
	install -D -m 0644 "$RECIPE_DIR/files/etc/conf.d/saphira-router" \
		"$PKGDEST/etc/conf.d/saphira-router"

	# Runtime identity. The core is unprivileged; this fragment creates the
	# identity and the two directories it needs, and makepkg generates the
	# install scripts from it.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-router" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-router"

	# Module directory. The core is usable with this empty, and with every
	# module absent; installing a module here makes its functionality appear
	# in the TUI without any interface change (D2 8).
	install -d -m 0755 "$PKGDEST/usr/lib/saphira-router/modules"

	# The core is usable with this directory empty. Refuse to package a module
	# if one ever reaches here: the fixtures are test-only, and shipping
	# mod_badabi.so to production would put a deliberately broken module on
	# every install for no reason. This is a build-time refusal so the mistake
	# cannot reach a published package.
	if ls "$PKGDEST"/usr/lib/saphira-router/modules/*.so >/dev/null 2>&1; then
		echo "ERROR: a module .so reached the payload; fixtures are test-only" >&2
		return 1
	fi

	# Default configuration. The daemon reads paths from the environment, not
	# from this file; it documents the layout and is the operator's reference.
	install -D -m 0640 \
		"$RECIPE_DIR/files/etc/saphira/saphira-router/router.conf" \
		"$PKGDEST/etc/saphira/saphira-router/router.conf"

	# Persistent log target, since the daemon logs to stderr/syslog.
	install -d -m 0755 "$PKGDEST/var/log/saphira-router"

	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-router/LICENSE"
}
