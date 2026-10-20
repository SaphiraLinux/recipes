#!/bin/sh

pkgname=saphira-install-tools
pkgver=0.1
pkgrel=22
# r22: single authoritative profile tree. The product and role profiles
# lived in saphira-image-creator's own files/profiles/ while the base,
# init and installer profiles lived here, with two kernels (bare
# saphira-kernel, disabled, versus the pinned 7.2.3 line) and two
# meanings of saphira-openrc. All product and role profiles move here;
# the kernel is pinned to saphira-kernel-7.2.3 everywhere; the thin
# saphira-openrc/saphira-systemd compositions are retired (superseded
# by the products of the same names). saphira-image-creator consumes
# this tree now; it ships no profiles of its own.
# r21: assembly writes /etc/.updated LAST (factory-state stamp): fresh
# targets skip first-boot ConditionNeedsUpdate units (notably
# systemd-hwdb-update, whose database ships prebuilt) instead of
# redoing that work during initial configuration, while later package
# upgrades still refire them exactly once.
# r20: replay caps.d fragments at assembly (ensure-caps --root):
# --no-scripts installs never converge file capabilities and APK
# records no xattr state, so capability-needing payloads (ping)
# installed dead - proven by non-root ping failing in 0.2.1.
# r19: two assembly defects proven by the 0.2.1 clean-root builds:
#   bootstrap cds into the empty target before invoking apk (apk
#   resolves a token against CWD first, so any profile intention
#   sharing its name with a CWD directory died "X: Is a directory");
#   the assembler skips accounts.d/*.legacy sidecars in the identity
#   replay (ensure-identity loads them itself via $FRAGMENT.legacy;
#   feeding dbus.legacy as a fragment killed systemd assembly).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira image/install tooling (bootstrap, chroot, genfstab, assembler, installer, imager) and install profiles'
license='BUSL-1.1'
origin=saphira-install-tools
repo=saphira
url=https://saphira.vm2.uk/

# Payload vendored from the live Egg install (the generation-zero Stage4
# mount is retired); bytes pinned below. r1 is the ABI migration:
#   depends: akadata-base-abi -> saphira-base-abi
#   profiles/base: akadata-base-abi -> saphira-base-abi;
#                  grub-common/grub-bios/grub-efi -> grub (monolithic)
#   profiles/server: php85-cli/php85-fpm/php85-opcache/php85-* extensions
#                    -> php85 (single package; extensions return when
#                    libcurl/oniguruma ports land)
#
# r14 installs every profile in files/profiles rather than a hand-kept list.
# r13 shipped saphira-chroot's --bind support and six new profiles and
# installed none of the profiles, because recipe_install enumerated them by
# name and nothing connected adding a profile to touching that list. An
# incomplete package reached the repository, which is exactly what the
# pkgrel discipline exists to prevent; r14 is the first revision whose
# payload actually matches its source.
depends="
	apk-tools
	coreutils
	saphira-base-abi
	util-linux
"
makedepends=""

recipe_build()
{
	local f
	for f in "$RECIPE_DIR"/files/saphira-* "$RECIPE_DIR"/files/profiles/*; do
		grep -q 'akadata-base-abi' "$f" && {
			echo "ERROR: unmigrated akadata-base-abi reference in $f" >&2
			return 1
		}
	done
	# Byte-pin the vendored payload.
	(cd "$RECIPE_DIR/files" && sha256sum -c files.sha256) || return 1
	# Profiles are DATA, and a data file that names a package which
	# does not exist produces an image that simply fails to install.
	# Every bare intention must be a real recipe, and every @-include
	# must resolve to a profile in this tree (with the historical
	# @saphira-stage4-/@akadata-stage4- alias spelling).
	local pkg entry target base
	for f in "$RECIPE_DIR"/files/profiles/*; do
		case $f in *.services) continue ;; esac
		awk '
			{ line = $0; sub(/#.*$/, "", line) }
			line ~ /^[[:space:]]*$/ { next }
			{ gsub(/^[ \t]+|[ \t]+$/, "", line); print line }
		' "$f" | while read -r pkg; do
			[ -n "$pkg" ] || continue
			case $pkg in
			@*)	entry=${pkg#@}
				case $entry in
				saphira-stage4-*|akadata-stage4-*)
					target=${entry#saphira-stage4-}
					target=${target#akadata-stage4-} ;;
				*)	target=$entry ;;
				esac
				[ -f "$RECIPE_DIR/files/profiles/$target" ] || {
					echo "ERROR: ${f##*/} includes missing profile: $pkg" >&2
					exit 1
				} ;;
			*[![:alnum:]._+-]*) continue ;;
			*)	# -dev/-doc names resolve to the base recipe (repo
				# convention): ncurses-dev is proven by ncurses/.
				base=$pkg
				case $base in
				*-dev) base=${base%-dev} ;;
				*-doc) base=${base%-doc} ;;
				esac
				[ -f "$SAPHIRA_RECIPE_ROOT/$base/recipe.sh" ] || {
					echo "ERROR: ${f##*/} names $pkg, which has no recipe" >&2
					exit 1
				} ;;
			esac
		done || return 1
	done
}

recipe_install()
{
	for tool in saphira-chroot saphira-bootstrap saphira-genfstab saphira-assemble-rootfs saphira-install; do
		install -D -m 0755 "$RECIPE_DIR/files/$tool" "$PKGDEST/usr/bin/$tool"
	done
	# Every profile is installed, not a hand-kept list. The list was the
	# defect: saphira-chroot's --bind support and six new profiles shipped in
	# a package that installed neither, because nothing about adding a
	# profile forced anyone to touch this loop. Two profiles added in one
	# sitting and both were silently absent from the published payload.
	# Enumerating the directory means a new profile cannot be forgotten.
	for profile in "$RECIPE_DIR"/files/profiles/*; do
		case $profile in
		*.services) continue ;;
		esac
		install -D -m 0644 "$profile" \
			"$PKGDEST/usr/share/saphira/profiles/$(basename "$profile")"
	done
	for sidecar in "$RECIPE_DIR"/files/profiles/*.services; do
		install -D -m 0644 "$sidecar" \
			"$PKGDEST/usr/share/saphira/profiles/$(basename "$sidecar")"
	done
	install -D -m 0644 "$RECIPE_DIR/files/saphira-bootstrap.8" \
		"$PKGDEST/usr/share/man/man8/saphira-bootstrap.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-profiles.5" \
		"$PKGDEST/usr/share/man/man5/saphira-profiles.5"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-assemble-rootfs.8" \
		"$PKGDEST/usr/share/man/man8/saphira-assemble-rootfs.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install.8" \
		"$PKGDEST/usr/share/man/man8/saphira-install.8"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-install-tools/LICENSE"
}
