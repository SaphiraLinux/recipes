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

# Also generate the udev hwdb fragment for USB vendor/model names
# (usb.ids -> 20-usb-vendor-model.hwdb, same mapping systemd's hwdb
# tooling produces). Target runs: udevadm hwdb --update
recipe_build()
{
	python3 - "$RECIPE_DIR/files/usb.ids" > "$SRC/20-usb-vendor-model.hwdb" <<'PYGEN'
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
	install -m 0644 "$RECIPE_DIR/files/pci.ids" "$PKGDEST/usr/share/hwdata/pci.ids"
	install -m 0644 "$RECIPE_DIR/files/usb.ids" "$PKGDEST/usr/share/hwdata/usb.ids"
	install -d "$PKGDEST/usr/lib/udev/hwdb.d"
	install -m 0644 "$SRC/20-usb-vendor-model.hwdb" \
		"$PKGDEST/usr/lib/udev/hwdb.d/"
}
