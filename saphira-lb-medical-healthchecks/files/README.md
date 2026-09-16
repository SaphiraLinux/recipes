# saphira-lb-medical-healthchecks

Healthcare-specific application health checks for Saphira load
balancers. BSL 1.1 licensed. Clean-room implementation. Depends on
`saphira-lb-healthchecks` (interface contract, common library), `dcmtk`
(DICOM SCU tools), curl, python3, and transitively the Saphira LB stack
(ipvsadm/LVS, ldirectord via resource-agents, haproxy).

## Package rule: named check = named capability

A check must fail when its named capability fails. `dicom.echo` never
degrades to "port open"; QIDO and WADO are separate checks because they
are different DICOMweb operations.

## Caller ABI vs check configuration

`$1`–`$5` (FWM/VIP, vport, real, rport, vsource) are the caller ABI —
nothing beyond `$5` is assumed from ldirectord/LVS/HAProxy. Everything
else is check-specific configuration with this resolution order:
positional `$6+` (manual/adapter convenience) > `LB_SAPHIRA_*`
environment > `/etc/saphira/lb-healthchecks.d/` config file > safe
default. DICOM checks accept `$6+` where it is useful:

    dicom.find:  $6 patient ID, $7 modality, $8 query level
    dicom.echo:  $6 called AE, $7 calling AE
    dicom.move:  $6 move destination AE (receiving SCP)
    dicom.qido / dicom.wado / dicom.stow / fhir: $6 URL

Per-install DICOM modality settings live in
`/etc/saphira/lb-healthchecks.d/dicom.find.conf` (or per service under
`dicom.find/<service>.conf`):

    LB_SAPHIRA_DICOM_PATIENT_ID=SAPHIRA-SYNTHETIC-HEALTHCHECK
    LB_SAPHIRA_DICOM_MODALITY=CT
    LB_SAPHIRA_DICOM_QUERY_LEVEL=PATIENT
    LB_SAPHIRA_DICOM_AET=SAPHIRA-HC
    LB_SAPHIRA_DICOM_AEC=MODALITY-SCP

## Safety classes

- **Cheap / continuous-safe**: C-ECHO, C-FIND (synthetic keys), QIDO,
  WADO, HL7 MLLP query (read-only synthetic), FHIR metadata.
- **Deep / opt-in (guard-gated)**: C-MOVE, C-STORE, STOW. These are
  state-changing; they hard-refuse (exit 2) unless
  `LB_SAPHIRA_STATE_CHANGING=1` AND their dedicated target is
  configured. Never enable them as high-frequency defaults.

## C-MOVE requirement

`lb.saphira.dicom.move` requires a **dedicated receiving SCP** (for
example a health-check `storescp` instance) configured as the move
destination via `LB_SAPHIRA_DICOM_MOVE_DEST`. movescu alone proves
nothing; the check fails closed without the destination.

## Checks

| Check | Class | Proves |
|---|---|---|
| lb.saphira.dicom.echo | continuous-safe | C-ECHO association + verification SCP |
| lb.saphira.dicom.find | continuous-safe | C-FIND cycle with synthetic non-patient keys |
| lb.saphira.dicom.move | opt-in | C-MOVE retrieve pipeline to dedicated receiving SCP |
| lb.saphira.dicom.store | opt-in | C-STORE of generated synthetic object |
| lb.saphira.dicom.qido | continuous-safe | QIDO-RS query -> 200 + application/dicom+json |
| lb.saphira.dicom.wado | continuous-safe | WADO-RS retrieve -> 200 + application/dicom |
| lb.saphira.dicom.stow | opt-in | STOW-RS store of synthetic object |
| lb.saphira.hl7.mllp | continuous-safe | MLLP QRY^A19 (synthetic, read-only) + valid ACK |
| lb.saphira.fhir | continuous-safe | FHIR CapabilityStatement served |

## Synthetic data

`lib/lb-saphira-dicom-synth.py` generates a minimal valid DICOM Part-10
Secondary Capture object (2x2 px) containing only synthetic healthcheck
data (PatientName `SAPHIRA^SYNTHETIC^HEALTHCHECK`, synthetic UIDs). No
upstream sample files are shipped. The HL7 query uses a synthetic
non-existent patient ID.

Per-check environment knobs are documented in each script header.
