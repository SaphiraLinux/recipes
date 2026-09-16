# Saphira platform profile: Apple M2 (T8112)

Reference machine: **macmer.vm2.uk** - MacBook Air 13" M2 2022 (board
j413, SoC T8112), Fedora Asahi Remix 44, Asahi kernel 7.1.13-401 16k.
DTBs present for j413/j415/j473/j493 (all M2 boards). Recon 2026-09-06,
read-only (no sudo on macmer); ESP evidence from the Sep-2025 install
at `/mnt/old-efi` (world-readable); live `/boot/efi` is root-only.
Docs: https://asahilinux.org/docs/platform/feature-support/m2/ and
https://asahilinux.org/docs/sw/u-boot/ (both read 2026-09-06).

This directory is a machine-profile library, not a package recipe: it
records how M2 boots and what a Saphira kernel/installer for it must
carry. Pi 4/400, Pi 5, M1/M3/M4 become sibling profiles later; the
`aarch64-akadata-linux-musl` toolchain target stays machine-neutral.

## Boot chain (evidenced on macmer)

Apple firmware (iBoot, reduced-security boot object) -> **m1n1 stage 1**
(machine-paired: that OS installation's ESP PARTUUID is embedded in
stage 1 when Asahi installs it) -> `<System ESP>/m1n1/boot.bin`
(**stage 2**, the updatable piece: m1n1 + Apple DTBs + gzipped U-Boot
per the Asahi formula `cat m1n1.bin dtbs/*.dtb <(gzip
u-boot-nodtb.bin)`, 4.5MB on macmer) -> **U-Boot** (AsahiLinux/u-boot,
`apple_m1_defconfig` covers ALL Apple Silicon despite the name; supplies
the pseudo-UEFI environment + FDT pointer, always falls through the
default ARM64 EFI path) -> `/EFI/BOOT/BOOTAA64.EFI` (PE32+ AArch64,
1MB, verified on disk) -> **shim** (`shimaa64.efi`) -> **GRUB**
(`grubaa64.efi`) -> stub `EFI/fedora/grub.cfg` (UUID-searches /boot,
loads `/boot/grub2/grub.cfg`) -> **Linux** (`vmlinuz-*` + initramfs,
also carries `dtb/` symlink, `System.map`, `.hmac`).

m1n1 here is v1.6.1 stage 1 + v1.6.1 stage 2 (from
`/proc/device-tree/chosen/asahi,m1n1-stage{1,2}-version`).

### Apple Silicon is explicitly not normal UEFI

Each OS owns its own System ESP / UEFI environment; there is no shared
ESP convention. The authoritative ESP for the RUNNING identity is
discoverable, not inferable from partition order:

- `/proc/device-tree/chosen/asahi,efi-system-partition` on macmer reads
  `8b50b2b3-19a1-4559-916d-31d860c31d0e`, which resolves via
  `/dev/disk/by-partuuid/` to `nvme0n1p10` - the live `/boot/efi`.
  The older ESP at nvme0n1p6 (`/mnt/old-efi`, ro) belongs to the prior
  install. Preserving the old ESP pair is valuable precisely because
  stage 1 is paired to one PARTUUID: lose the ESP and the installed
  stage 1 points at nothing.
- Asahi warns against two installed OSes independently updating the
  same `m1n1/boot.bin`: stage 2 is per-OS updatable state, and
  concurrent writers can strand or brick the boot path. Saphira must
  treat a foreign `boot.bin` as read-only evidence, never rewrite it
  in place - install by backup-and-concatenate to a Saphira-owned ESP.

### Platform split (the abstraction this library enforces)

- **Immutable / machine-paired** (observe, never modify): Apple stub +
  iBoot policy + m1n1 stage 1 (PARTUUID-paired) + Apple firmware blobs.
- **Saphira-maintainable**: m1n1 stage 2 + DTBs + U-Boot + EFI loader
  (shim/GRUB or direct EFI-stub kernel later) + kernel + initramfs +
  vendor firmware set with manifest SHAs.

### Source hierarchy

The M2 feature-status page tells what hardware support has reached
mainline; it is NOT the platform definition. Boot process and
platform quirks (m1n1 guide, U-Boot doc, open-os-interop) are primary;
feature tables are consulted only for kernel-config scoping.

ESP inventory (`/mnt/old-efi`): `m1n1/boot.bin`, `EFI/BOOT/` (BOOTAA64,
bootx64, fb/mm aa64 EFIs), `EFI/fedora/` (shim, GRUB, CSV, stub cfg),
`ubootefi.var` (976B U-Boot EFI variable store), `vendorfw/`
(Apple firmware: `firmware.cpio`/`firmware.tar` + `manifest.txt` with
per-file SHAs - brcm WiFi, asmedia USB-XHCI `asm2214a-apple.bin`,
etc.), `asahi/` (macOS installer remnants: BuildManifest,
kernelcache.release.mac14g, all_firmware.tar.gz). Two ESPs exist on
macmer (`/boot/efi` nvme0n1p10 live, `/mnt/old-efi` nvme0n1p6 prior
install, ro). U-Boot console: interrupt default script (`bootd`,
`run bootcmd_usb0`, `nvme scan`, `ls nvme 0:4 /`); no `poweroff`
command on Apple Silicon. EFI vars visible: `efivarfs` mounted,
`efibootmgr` needs root (unavailable to recon).

## Saphira kernel policy for t8112 (binding when the recipe lands)

- **16K pages** (`CONFIG_ARM64_16K_PAGES=y`) - NOT 4K. Non-negotiable;
  Asahi userspace assumes it.
- `CONFIG_ARM64_VA_BITS_48`, `CONFIG_SMP=y`, `CONFIG_EFI_STUB=y` +
  `CONFIG_EFI_GENERIC_STUB=y` (kernel is directly UEFI-bootable -
  future simplification past GRUB).
- Apple/ARM-Apple block from the live 7.3.0-rc2 build in
  `/usr/src/linux/.config` (13 symbols): see `m2-kernel-options.txt`.
  Includes DART, AIC, RTKIT, mailbox, cpufreq, NVMe-Apple, ATC PHY.
- DTB: `t8112-j413.dtb` for macmer (j415/j473/j493 later).
- Firmware: `vendorfw` manifest model (per-file SHA) is the pattern to
  copy; kernel needs brcm/asmedia blobs in `/lib/firmware`. VERIFY
  redistribution rights before packaging (Apple firmware).
- Initramfs required (Fedora ships 46-70MB images; Saphira shape TBD).

## M2/T8112 feature posture (Asahi docs, 2026-09-06)

Upstream already: NVMe 5.19, PCIe 5.16/6.4, AICv2 5.18, cpufreq 6.2,
PMU 6.4, UART/I2C/GPIO/USB-PD 5.13-5.16, WiFi 6.1, BT 6.2, DART 6.3,
SPI/SPI-NOR 6.15, SMC/SPMI 6.16/6.18, RTC/USB2/USB3 7.0, battery 7.1.
linux-asahi only: DCP, GPU, video decoder, cpuidle (WFI/WFE hack, never
upstreamable), suspend, speakers/mics/webcam/kb/touchpad, HDMI out.
WIP: Thunderbolt, DP Alt Mode, SEP. TBA: video encoder, ProRes, TouchID
(all M2), ANE out-of-tree. Full tables at the feature-support URL
above; re-check before freezing a Saphira t8112 config. Net: base M2
T8112 support (NVMe, cpufreq, DART, SMC, RTC and much more) is
increasingly mainline, while display/GPU/sleep and several
peripherals remain linux-asahi territory - the Saphira t8112 kernel
line will track linux-asahi, not vanilla, until that flips.

## Saphira next steps (not this commit)

1. `saphira-kernel` t8112 line: 16k-page arm64 config seeded from the
   reference options + Asahi patches (separate track from x86 lines).
2. m1n1 + U-Boot packaging track (Fedora `uboot-tools` /
   `asahi-scripts` as reference; backup-and-concatenate install rule
   so a bad `boot.bin` is recoverable from macOS by rename).
3. DTB packaging + firmware bundle with manifest SHAs.
4. Machine profiles: j413 first; j415/j473/j493, then M1/M3/M4.
5. armer (Pi 400, Alpine today) is a SEPARATE profile, not this one.

Explicitly out of scope: macOS boot-policy changes, TouchID/SEP
promises, ANE packaging, 4K-page variants.
