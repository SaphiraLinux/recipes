# Saphira Linux recipes

Egg is the native Saphira v0.1 build controller used to produce Saphira v0.2. `/recipes` is the writable canonical native recipe catalogue. `/reference-package-recipes` and `/cports` are read-only historical/upstream references, in that order. `/out` holds package/repository output and `/build` is disposable package scratch space.

## Native build boundary

Normal operation is `buildpkg PACKAGE`. It resolves only that request's closure and writes its versioned JSON plan inside `/build/PACKAGE.buildpkg`. A satisfying trusted repository APK is reused; a local producer is built only when the repository cannot satisfy the dependency. An explicit top-level request always builds the current native recipe.

One visible workspace is used per top-level build. Each workspace keeps its own OverlayFS upper (`upper/`) and workdir (`work/`), while `/build/PACKAGE.buildpkg/root` remains the merged full-root view every Bubblewrap session sees. The merged view is mounted by a visible per-workspace overlay holder process (recorded in `overlay-holder.json`) inside its own user/mount namespace; the holder is terminated (unmounting the overlay cleanly) when the build attempt finishes, whether it passes or fails. Successful builds then remove the workspace; failed builds retain `upper/`, logs, plan and `OVERLAY-RECOVER.txt` (re-mount the merged view per its instructions) so the failure stays diagnosable, and a leftover holder self-terminates once its workspace is removed. Package dependencies are installed only into that merged root. `buildpkg`, `resolvepkg`, and `makepkg` run without root or sudo and never change Egg's package database; `buildpkg-single` is the internal namespace worker (it refuses outside the isolated build namespace) - the supported frontend is `buildpkg PACKAGE`.

The one physical canonical build root lives at `/build/rootfs_overlay/base` (visible state and lock files under `/build/rootfs_overlay/state/`; no hidden directories). It is created once by installing the repository package seed — package names only, no host files — and is immutable while builds run. Its identity is pinned by a fingerprint over the build seed and the architecture, recorded in `state/base.json`; buildpkg rebuilds the base into `rootfs_overlay/base.new` and swaps it in when the fingerprint no longer matches the current seed definition, or when `SAPHIRA_BASE_REBUILD=1` forces it. Retired `base.old-*` directories are removed unless a live overlay still references them.

Egg's Saphira v0.1 system is the controller host, never a build input: no Egg file crosses into a build root. The whole foundation — musl loader/libc, libc/POSIX and kernel ABI headers, CRT objects, toolchain runtimes — arrives as signed repository APKs named in `SAPHIRA_BUILD_SEED`. Toolchain and utility packages such as GCC, binutils, bash, and coreutils likewise come from repository APKs. Everything on Egg outside APK ownership is invisible to recipe execution.

Saphira is a pure 64-bit distribution with the clean `/lib` and `/usr/lib` layout. `/lib64` and `/usr/lib64` are forbidden in both the bootstrap seed and package payloads.

## Base package sets

The eventual foundational package set is init-neutral. “@base” is only a conceptual shorthand; literal APK names avoid `@`, which apk-tools reserves for repository tags. These are ordinary recipe/meta-package relationships, not a central dependency catalogue:

- `saphira-base`: libc/loader, filesystem layout, apk, shell, core runtime, networking essentials, and kernel-facing essentials.
- `saphira-base-openrc`: `saphira-base`, OpenRC, and Saphira defaults.
- `saphira-base-systemd`: `saphira-base`, systemd, and Saphira-d defaults.

## Boot architecture

The Saphira boot path is deliberately minimal and has no early userspace:

    kernel -> real ext4 root filesystem -> /sbin/init

Everything the kernel needs before that is built in (`=y`), not a module:
ext4, virtio block/PCI/net/console, devtmpfs, the 8250 console driver. Images
ship no initrd and no initramfs, and none is generated, referenced or
troubleshoted. An initrd may become appropriate later for a configuration
that genuinely requires early userspace - notably a ZFS root - and that is
separate future work, not a current defect to fix.

The kernel names exactly one console, the VGA (`console=tty0`), so
`/dev/console` is always the console a machine's operator can see and type
on. Firstboot is driven entirely through `/dev/console` (OpenRC init script
redirection, systemd `TTYPath`), which is why a second `console=ttyS0` on
the packaged command line was a real defect: on hardware without a serial
port it left firstboot with no visible console at all. A deployment that
genuinely has a serial console adds `console=ttyS0` to its own kernel line.

Firstboot itself is an init-level service in the ordinary boot sequence -
GRUB, kernel, real root, init, essential boot and platform setup, a clean
console, firstboot, and only then login and the services that need a
configured identity and network. It is never a boot mode, and its address
mode for every interface is an explicit operator choice: DHCP and DHCPv6
are selections, never defaults, and an empty answer never changes a
decision. `dhcpcd` ships as an available capability, is never enabled or
started just by being installed, and never writes the resolver. The
normative rules are in `RECIPE_RULES.md`.

## Artifacts and administration

Successful unsigned artifacts are promoted to a visible `*-ready` transaction below the configured incoming directory; successful build scratch is removed. Failed workspaces retain a trusted `FAILED` marker. Unmarked workspace collisions are refused.

`sign-apk-repo` is the explicit privileged signing/publication boundary. It consumes only complete ready transactions, verifies immutable filenames and identities, signs and verifies APKs and both compatible indexes, then marks transactions `-published`. `installpkg` is the separate explicit privileged live-system installation boundary.

Before `saphira-packager.apk` exists, an administrator may explicitly run `saphira-packager/files/install-saphira-packager` to install the controller scripts, configuration, and bootstrap manifest. It installs no recipe dependencies and publishes nothing. Once the signed APK is installed, the APK owns the permanent `/usr/bin` tools and `/etc/saphira` configuration.
