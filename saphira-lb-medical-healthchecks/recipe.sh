#!/bin/sh

pkgname=saphira-lb-medical-healthchecks
pkgver=2026.09
pkgrel=2
pkgarch=noarch
pkgdesc='Saphira healthcare-specific LB healthchecks (DICOM/DICOMweb/HL7/FHIR under /var/lib/lb/saphira)'
license=BUSL-1.1
origin=saphira-lb-medical-healthchecks
repo=saphira
url=https://saphira.vm2.uk/

# Payload is authored in files/ (clean-room, MIT); no upstream source.
# Depends on the generic library (which carries the LB stack) and dcmtk
# for the DICOM SCU tools.
depends="
	dcmtk
	saphira-lb-healthchecks
"
makedepends=""

recipe_build()
{
	local f
	for f in "$RECIPE_DIR"/files/lb.saphira.*; do
		# lb.saphira.hl7.mllp is python3 (validated by py_compile below).
		case "$(basename "$f")" in lb.saphira.hl7.mllp) continue ;; esac
		sh -n "$f" || return 1
	done
	PYTHONPYCACHEPREFIX="$BUILDDIR/pycache" python3 -m py_compile \
		"$RECIPE_DIR/files/lib/lb-saphira-dicom-synth.py" \
		"$RECIPE_DIR/files/lb.saphira.hl7.mllp" || return 1
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/var/lib/lb/saphira"
	for f in "$RECIPE_DIR"/files/lb.saphira.*; do
		install -m 0755 "$f" "$PKGDEST/var/lib/lb/saphira/$(basename "$f")"
	done
	install -D -m 0644 "$RECIPE_DIR/files/lib/lb-saphira-dicom-synth.py" \
		"$PKGDEST/usr/share/saphira/lb-medical-healthchecks/lib/lb-saphira-dicom-synth.py"
	install -D -m 0644 "$RECIPE_DIR/files/README.md" \
		"$PKGDEST/usr/share/doc/saphira-lb-medical-healthchecks/README.md"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-lb-medical-healthchecks/LICENSE"
	find "$PKGDEST" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
}
