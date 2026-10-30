#!/bin/sh

pkgname=android-tools
pkgver=37.0.0_p1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Android platform tools from AOSP source (adb, fastboot and companions)"
license="Apache-2.0 AND GPL-3.0-or-later"
origin=android-tools
repo=main
url=https://github.com/nmeum/android-tools
vendor=https://github.com/nmeum/android-tools/releases/download/37.0.0p1/android-tools-37.0.0p1.tar.xz
sha256=2c6de1abe16b211c7d9f59276217e14fd9e0e18b20e331d3c84358f5dffd576e

# Tarball sha512 cross-checked against Alpine's pin (f2943637...,
# identical bytes). nmeum CMake build over AOSP sources; no Rust
# (mDNS off), no Go (removed upstream in 37.0.0), C++20 via gcc.
# Runtime edges are DT_NEEDED providers plus the python3 the
# shipped mkbootimg/avbtool scripts exec (RUNTIME gate verifies).
# gcc-libs for the C++ binaries (same closure as abseil/gtest/llvm).
depends="
    brotli
    fmt
    gcc-libs
    libusb
    lz4
    pcre2
    protobuf
    python3
    zlib
    zstd
"

makedepends="
    abseil-cpp-dev
    binutils
    brotli-dev
    cmake
    fmt-dev
    gcc
    gtest-dev
    libusb-dev
    lz4-dev
    make
    pcre2-dev
    pkgconf
    protobuf-dev
    udev-dev
    zlib-dev
    zstd-dev
"

# System libraries throughout (bundled fmt/libusb off, matching
# upstream defaults explicitly); mDNS stays off (needs Rust +
# corrosion, absent); udev on (device enumeration is core adb
# function, libudev present); vendor patches on (documented flow).
# Tests off (BUILD_TESTING cached off upstream), so gtest is
# deliberately NOT consumed - add it if a test target ever needs it.
# udev RULES (51-android.rules, M0Rf30 20260922, GPL-3.0-or-later,
# same license already carried): extracted from its own vendored
# tarball (sidecar-verified) and mapped GROUP=adbusers to Saphira's
# seed plugdev group (distro integration, same class as udev's
# sysctl-callout rewrite; syntax proven via udevadm verify). The
# fragment creates plugdev at install (seed rows alone never
# materialize it - proven absent live). No daemon, no user.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/android-tools-37.0.0p1.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/android-tools-37.0.0p1.tar.xz" \
		-C "$BUILDDIR" --strip-components=1
	tar -xzOf "$RECIPE_DIR/files/android-udev-rules-20260922.tar.gz" \
		android-udev-rules-20260922/51-android.rules \
		| sed 's/GROUP="adbusers"/GROUP="plugdev"/' \
		> "$BUILDDIR/51-android.rules" || return 1
	cmake -S "$BUILDDIR" -B "$BUILDDIR/build" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DANDROID_TOOLS_USE_BUNDLED_FMT=OFF \
		-DANDROID_TOOLS_USE_BUNDLED_LIBUSB=OFF \
		-DANDROID_TOOLS_USE_BUNDLED_CORROSION=OFF \
		-DANDROID_TOOLS_ADB_ENABLE_MDNS=OFF \
		-DANDROID_TOOLS_LIBUSB_ENABLE_UDEV=ON \
		-DANDROID_TOOLS_PATCH_VENDOR=ON
	cmake --build "$BUILDDIR/build"
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR/build"
	install -D -m 0644 "$BUILDDIR/51-android.rules" \
		"$PKGDEST/lib/udev/rules.d/51-android.rules"
	# Device-access identity: plugdev group declaration (identical
	# to the seed row, converges); makepkg generates install scripts
	# ONLY from this payload copy.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/android-tools" \
		"$PKGDEST/usr/share/saphira/accounts.d/android-tools"
	# Payload proof: the two named tools plus the rules file and the
	# identity fragment.
	for p in usr/bin/adb \
		usr/bin/fastboot \
		lib/udev/rules.d/51-android.rules \
		usr/share/saphira/accounts.d/android-tools; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: android-tools payload is missing $p" >&2
			return 1
		}
	done
}
