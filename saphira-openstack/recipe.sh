#!/bin/sh
#
# saphira-openstack: operator-driven OpenStack installer foundation.
#
# noarch, files-only package: a menu-driven wizard (init), an inspector
# (inventory) and a read-only planner (plan) over one validation engine.
# No upstream source: the payload is this tree's files/, following the
# saphira-network controller-package idiom.
#
# The package installs tooling only. It ships no init units (it is not a
# daemon), runs no scripts, and configures nothing on the machine.

pkgname=saphira-openstack
pkgver=0.1
pkgrel=3
pkgarch=noarch
pkgdesc='Saphira native OpenStack installer foundation (init, inventory, plan)'
license='BUSL-1.1'
origin=saphira-openstack
repo=saphira
url=https://saphira.vm2.uk/

depends=""
makedepends=""

recipe_build()
{
	tool=$RECIPE_DIR/files/saphira-openstack
	# syntax-check every shipped shell file
	for f in "$tool" "$RECIPE_DIR"/files/lib/*.sh; do
		sh -n "$f" || {
			echo "ERROR: $f does not parse" >&2
			return 1
		}
	done
	# catalogs are well-formed: header plus consistent column counts
	for cat in services networks storage operations; do
		catfile=$RECIPE_DIR/files/catalog/$cat.tsv
		[ -f "$catfile" ] || {
			echo "ERROR: catalog is missing: $catfile" >&2
			return 1
		}
		# documentation lines (#) and blanks are not data: the
		# header is the first data row, every data row matches it
		data=$(grep -v -e '^#' -e '^[[:space:]]*$' "$catfile")
		cols=$(printf '%s\n' "$data" | head -1 | awk -F'|' '{ print NF }')
		[ "$cols" -ge 2 ] || {
			echo "ERROR: catalog $cat has no fields" >&2
			return 1
		}
		bad=$(printf '%s\n' "$data" | awk -F'|' -v c="$cols" 'NF != c { n++ } END { print n + 0 }')
		[ "$bad" -eq 0 ] || {
			echo "ERROR: catalog $cat has $bad malformed rows" >&2
			return 1
		}
	done
	# the shipped examples must validate through the engine
	for ex in single-node multihost; do
		sh "$tool" inventory --file "$RECIPE_DIR/files/examples/$ex.ini" \
			--check >/dev/null 2>&1 || {
			echo "ERROR: example $ex.ini does not validate" >&2
			return 1
		}
	done
	# the tool must refuse to touch a live path, by construction:
	# no unit files, no hooks, no maintainer scripts
	[ ! -d "$RECIPE_DIR/files/units" ] || {
		echo "ERROR: saphira-openstack must not ship init units" >&2
		return 1
	}
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/sbin" \
		"$PKGDEST/usr/libexec/saphira/openstack" \
		"$PKGDEST/usr/share/saphira/openstack/catalog" \
		"$PKGDEST/usr/share/saphira/openstack/examples" \
		"$PKGDEST/usr/share/doc/saphira-openstack" \
		"$PKGDEST/usr/share/licenses/saphira-openstack"

	install -m 0755 "$RECIPE_DIR/files/saphira-openstack" \
		"$PKGDEST/usr/sbin/saphira-openstack"
	for f in engine wizard inventory plan detect; do
		install -m 0755 "$RECIPE_DIR/files/lib/$f.sh" \
			"$PKGDEST/usr/libexec/saphira/openstack/$f.sh"
	done
	for cat in services networks storage operations; do
		install -m 0644 "$RECIPE_DIR/files/catalog/$cat.tsv" \
			"$PKGDEST/usr/share/saphira/openstack/catalog/$cat.tsv"
	done
	for ex in single-node multihost; do
		install -m 0644 "$RECIPE_DIR/files/examples/$ex.ini" \
			"$PKGDEST/usr/share/saphira/openstack/examples/$ex.ini"
	done
	install -m 0644 "$RECIPE_DIR/files/inventory-format.txt" \
		"$PKGDEST/usr/share/saphira/openstack/inventory-format.txt"
	install -m 0644 "$RECIPE_DIR/files/OPENSTACK-ROADMAP.txt" \
		"$PKGDEST/usr/share/saphira/openstack/OPENSTACK-ROADMAP.txt"
	install -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/saphira-openstack/README"
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-openstack/LICENSE"

	# payload assertions: every installed path the tool resolves at
	# runtime must be present, exactly as the library expects
	for p in \
		usr/sbin/saphira-openstack \
		usr/libexec/saphira/openstack/engine.sh \
		usr/libexec/saphira/openstack/wizard.sh \
		usr/libexec/saphira/openstack/inventory.sh \
		usr/libexec/saphira/openstack/plan.sh \
		usr/libexec/saphira/openstack/detect.sh \
		usr/share/saphira/openstack/catalog/services.tsv \
		usr/share/saphira/openstack/catalog/networks.tsv \
		usr/share/saphira/openstack/catalog/storage.tsv \
		usr/share/saphira/openstack/catalog/operations.tsv \
		usr/share/saphira/openstack/examples/single-node.ini \
		usr/share/saphira/openstack/examples/multihost.ini \
		usr/share/saphira/openstack/inventory-format.txt \
		usr/share/saphira/openstack/OPENSTACK-ROADMAP.txt \
		usr/share/doc/saphira-openstack/README \
		usr/share/licenses/saphira-openstack/LICENSE \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-openstack payload is missing $p" >&2
			return 1
		}
	done
	# the package must not imply a running service: no init units, no hooks
	[ ! -d "$PKGDEST/etc/init.d" ] || {
		echo "ERROR: saphira-openstack must not ship init units" >&2
		return 1
	}
}
