#!/bin/sh
# lb.saphira.dicom.move - DICOM C-MOVE retrieve pipeline (deep, opt-in).
# REQUIRES a dedicated receiving SCP (e.g. a health-check storescp
# instance) configured as the move destination - movescu alone proves
# nothing. Fails closed without configuration. Guard-gated: never a
# casual high-frequency default check.
# Configuration ($6 convenience; env/conf otherwise):
#   $6  move destination AE  LB_SAPHIRA_DICOM_MOVE_DEST (REQUIRED)
#       LB_SAPHIRA_STATE_CHANGING=1          explicit opt-in
#       LB_SAPHIRA_DICOM_PATIENT_ID          synthetic query key
# Copyright (c) 2026 AKADATA. MIT licensed.
. /usr/share/saphira/lb-healthchecks/lib/lb-saphira-common.sh
lb_init "$@"
[ "${LB_SAPHIRA_STATE_CHANGING:-0}" = "1" ] || exit 2
DEST="${6:-${LB_SAPHIRA_DICOM_MOVE_DEST:-}}"
[ -n "$DEST" ] || exit 2
exec movescu -aet "${LB_SAPHIRA_DICOM_AET:-SAPHIRA-HC}" \
	-aec "${LB_SAPHIRA_DICOM_AEC:-ANY-SCP}" \
	-aem "$DEST" \
	-ta "$LB_TIMEOUT" \
	-P \
	-k QueryRetrieveLevel=PATIENT \
	-k "PatientID=${LB_SAPHIRA_DICOM_PATIENT_ID:-SAPHIRA-SYNTHETIC-HEALTHCHECK}" \
	"$LB_REAL" "${LB_RPORT:-104}"
