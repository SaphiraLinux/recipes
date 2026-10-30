# October-2026 Node.js CVE regression suite

Release gate for the 2026-10-21 security releases, not a smoke-test
collection. Runs automatically in the builder TEST stage via
`../test.sh` (exit 0 = ship, anything else = stop). Also runnable by
hand against any `node` binary for red/green work.

## Protocol

Each case exits `0` PASS, `1` FAIL, `2` SKIP (version-gated only).
Anything else (timeout where a hang is not the symptom, crash outside
the Brotli oracle, missing feature) is ERROR and fails the gate. SKIP
is explicit and counted; it is never silent.

## Oracle boundaries (read before extending)

- **Brotli (111497):** the gate proves deterministic rejection of the
  upstream regression input with the exact error. It does NOT prove
  memory safety. Memory safety rests on upstream fix inspection
  (cherry-pick `0ed4268a4401abcb44720963`, `BLOCK_SWITCH` marker
  asserted in `recipe_build`). A hang here is FAIL (vulnerable
  accumulation), never a harness quirk.
- **TLS (105483/106069/106072):** unit-level `checkServerIdentity`
  assertions plus `tls-live.js`, which runs a real handshake and feeds
  the wire certificate through the same verifier. Expiry is out of
  scope for identity checks by construction.
- **dns (105482):** rejection must carry `ERR_INVALID_ARG_VALUE`;
  any other error (or a query attempt) is red, not "also an error".
- **keep-alive (105481):** 64KB of garbage makes pre-arrival certain,
  so old code misparses deterministically and new code destroys
  deterministically. No timing luck on either side.
- **snapshot (106074):** cross-run UUID equality is computationally
  impossible by chance, so equality is deterministic red.
- **permission (106073):** only the outside-grant throw counts.
  Upstream additionally requires FULL grants for symlink creation
  itself, so no escape-link probe is constructed; the read-side probe
  is the CVE's exact shape.

## Fixtures

`snakeoil-cert.pem` / `snakeoil-key.pem`: test-only self-signed pair
(CN=localhost; SANs DNS:localhost, DNS:127.0.0.1, IP:127.0.0.1,
IP:87.0.0.1), valid 2026-10-23 – 2036-10-21. NEVER deployed; used only
by `tls-live.js`, which disables chain validation and tests identity
alone. Regenerate with:
`openssl req -x509 -newkey rsa:2048 -keyout snakeoil-key.pem -out
snakeoil-cert.pem -days 3650 -nodes -subj '/CN=localhost' -addext
'subjectAltName=DNS:localhost,DNS:127.0.0.1,IP:127.0.0.1,IP:87.0.0.1'`
and update the validity dates above.

## Sync rule

This directory is mirrored between `nodejs/` and `nodejs22/`
(the builder runs each recipe's own tree). Keep both identical; the
ONLY intended difference is the 105483 version gate in `test.sh`.
