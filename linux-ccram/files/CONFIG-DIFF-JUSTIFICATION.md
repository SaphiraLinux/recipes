# CONFIG-DIFF-JUSTIFICATION — meta-cram config vs 7.2.9-ccram

Method: direct `diff` of the two shipped configs (both resolved).
The ccram config is derived from the meta-cram config, which itself
derives from the normal Saphira kernel config (`config-7.2.2-akadata`
plus `cram-config.fragment`, resolved by `make olddefconfig` — see
`CONFIG-DIFF-JUSTIFICATION.md` in `linux-saphira-meta-cram`). So the
chain normal → meta-cram → ccram is fully documented, and this file
only has to justify the last step.

## The complete delta (2 lines, nothing else)

```diff
-CONFIG_LOCALVERSION="-meta-cram"
+CONFIG_LOCALVERSION="-ccram"
...
+CONFIG_CCRAM_SYSRAM=y
...
-# CONFIG_DRM_FBDEV_EMULATION is not set
+CONFIG_DRM_FBDEV_EMULATION=y
```

- `LOCALVERSION="-ccram"` — release identity: distinct
  `/lib/modules/7.2.9-ccram`, distinct `/boot` names. Coexistence with
  every normal Saphira kernel is structural (separate image, System.map,
  config, module tree, GRUB entry); no normal kernel is replaced or
  removed by installing this package.
- `CONFIG_CCRAM_SYSRAM=y` — the Saphira-original backend (bool, default
  n). Deps (`CRAM`, `NUMA`, `MEMORY_HOTPLUG`, `X86_64`) are already `y`
  in the parent; it selects nothing, so `make olddefconfig` adds no
  ripple (proven: the diff above is the entire difference).
- `CONFIG_DRM_FBDEV_EMULATION=y` — restores the local boot console to
  7.2.x parity. On 7.2.9 the DRM client rework gates
  `drm_client_setup_*` behind this symbol (see
  `drivers/gpu/drm/clients/Kconfig`); without it i915 initialises but
  creates no fb0 and fbcon never takes over, so UEFI boxes show no boot
  progress. The 7.2.x kernels predate the split and bind `i915drmfb`
  unconditionally. Selects `DRM_CLIENT_SETUP` (and
  `FRAMEBUFFER_CONSOLE_DETECT_PRIMARY`); verified no further ripple.

## Exact final config delta (post-`olddefconfig`, proven 2026-10-11)

Resolving the shipped config against the 7.2.9 tree yields, beyond the
three lines above, exactly these selected symbols (and nothing else):

```text
CONFIG_DRM_CLIENT_SETUP=y
CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y
CONFIG_DRM_CLIENT_DEFAULT="fbdev"
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
```

This matches the working fbdev client chain of the operator-built
7.2.3 on minimer (`/boot/config-7.2.3-akadata` there — note: that
box's 7.2.3 was built from a different config than this repo's
`config-7.2.3-akadata`, which predates the fbdev-client split and
carries none of these symbols).

## Gate design (why two assertions)

An early revision of this recipe asserted only the pre-resolution
seed config. That is insufficient in general: `olddefconfig` can flip
a symbol whose dependencies are unmet, and the seed gate would miss
it. The recipe therefore asserts twice: once on the seed (fail fast
on fragment typos) and once on the resolved `.config` (authoritative
— this is what the payload is built from). The resolution assertion
checks the fragment's symbols with exact values plus the four
selected symbols above; anything else unexpected fails the build.

## Everything else (inherited, already justified)

All other symbols — the CRAM service, the DAX/KMEM/NVDIMM test-backend
closure, the 7.2.9-new Kconfig defaults, the Saphira baseline — are
identical to `config-7.2.9-meta-cram-akadata` and justified in that
recipe's `CONFIG-DIFF-JUSTIFICATION.md`. This recipe asserts the
CCRAM-family symbols at build time (see `recipe.sh`:
`check_ccram_config_delta`): the fragment's symbols must be present
with exactly these values, and no other `CONFIG_CCRAM_*` symbol may
appear. Any future delta must extend the fragment and this document
together — an unexplained config line fails the build, never ships
silently.
