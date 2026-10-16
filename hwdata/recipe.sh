#!/bin/sh

pkgname=hwdata
pkgver=2026.08.30
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Hardware identification databases (pci.ids + usb.ids)'
license='GPL-2.0-or-later OR BSD-3-Clause'
origin=hwdata
repo=saphira
url='https://pci-ids.ucw.cz/ https://www.linux-usb.org/usb.ids'
# Data snapshot 2026-08-30 from the canonical upstream sources:
#   pci.ids https://raw.githubusercontent.com/pciutils/pciids/master/pci.ids
#   usb.ids http://www.linux-usb.org/usb.ids
# Data files, not release tarballs; refresh = re-download + sha256 + pkgrel.
# Reproducible staging: exact bytes pinned below, staged through $SRC
# (under /build) with sha256 verification. Existing files/ inputs are
# kept until the staged path is proven; do not delete them. The public
# mirror never carries usb.ids (latin-1, fails strict UTF-8 gate);
# it stays ignored/untracked by decision, not as a generated binary.
pci_ids_vendor=https://raw.githubusercontent.com/pciutils/pciids/master/pci.ids
pci_ids_sha256=b63f063ea3427516e5af68cab4c84abf8562a89fd0afbc7e0b94fd50408e3f22
usb_ids_vendor=https://www.linux-usb.org/usb.ids
usb_ids_sha256=f5a48b0cc8dae1607c2f0bae6b8dc13f2ecef69dbeaeaf34b4be8e280d34dba4

# Also generate the udev hwdb fragment for USB vendor/model names
# (usb.ids -> 20-usb-vendor-model.hwdb, same mapping systemd's hwdb
# tooling produces). Target runs: udevadm hwdb --update
recipe_build()
{
	# Stage exact pinned bytes through $SRC (under /build) with
	# verification; fails closed on drift. Downloads would land here
	# as well (curl to $SRC + sha256 -c), but files/ inputs are kept
	# until that path is proven, so copy + verify for now.
	STAGED_PCI="$SRC/pci.ids"
	STAGED_USB="$SRC/usb.ids"
	cp "$RECIPE_DIR/files/pci.ids" "$STAGED_PCI"
	cp "$RECIPE_DIR/files/usb.ids" "$STAGED_USB"
	echo "$pci_ids_sha256  $STAGED_PCI" | sha256sum -c -
	echo "$usb_ids_sha256  $STAGED_USB" | sha256sum -c -
	python3 - "$STAGED_USB" > "$SRC/20-usb-vendor-model.hwdb" <<'PYGEN'
import sys
out = sys.stdout
vendor = None
product = None
def esc(s):
    return s.strip().replace("\n", " ").replace("  ", " ")
import re
for line in open(sys.argv[1], encoding="latin-1"):
    if line.startswith("#") or not line.strip():
        continue
    if line.startswith("  "):
        if not re.match(r"^  [0-9a-f]{4}  ", line):
            continue
        if line.startswith("    "):
            continue
        pid, name = line.strip().split("  ", 1)
        product = esc(name)
        out.write(f"\nusb:v{int(vendor, 16):04X}p{int(pid, 16):04X}*\n")
        out.write(f" ID_MODEL_FROM_DATABASE={product}\n")
    else:
        if not re.match(r"^[0-9a-f]{4}  ", line):
            continue
        vid, name = line.strip().split("  ", 1)
        vendor = vid
        out.write(f"\nusb:v{int(vid, 16):04X}*\n")
        out.write(f" ID_VENDOR_FROM_DATABASE={esc(name)}\n")
PYGEN
	[ -s "$SRC/20-usb-vendor-model.hwdb" ] || { echo "hwdb generation failed" >&2; return 1; }
}

recipe_install()
{
	install -d "$PKGDEST/usr/share/hwdata"
	install -m 0644 "$SRC/pci.ids" "$PKGDEST/usr/share/hwdata/pci.ids"
	install -m 0644 "$SRC/usb.ids" "$PKGDEST/usr/share/hwdata/usb.ids"
	install -d "$PKGDEST/usr/lib/udev/hwdb.d"
	install -m 0644 "$SRC/20-usb-vendor-model.hwdb" \
		"$PKGDEST/usr/lib/udev/hwdb.d/"
}
