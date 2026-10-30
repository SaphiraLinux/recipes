# openjpeg patches

## osv-2025-219-heap-overflow.patch

Backport of upstream commit `d33cbecc148d3affcdf403211fddc2cc5d442379`
("Fix heap buffer overflow in opj_j2k_read_sod", 10 Feb 2026), which
fixes OSV-2025-219 (OSS-Fuzz heap-buffer-overflow WRITE in
`opj_j2k_read_tile_header` via a crafted tile-part index).

Why a backport is needed: upstream declared the repository
unmaintained and the fix never shipped in any tagged release —
2.5.4 (the newest tag, September 2025) is still vulnerable, with no
CVE assigned. Shipping 2.5.4 unpatched into an imaging stack that
processes untrusted files would repeat the exact failure mode this
collection exists to close (cf. Pillow CVE-2026-112403). The patch
applies cleanly to the 2.5.4 tree (verified with `patch --dry-run`
at recipe-authoring time; the build fails closed otherwise).
