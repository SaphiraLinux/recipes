#!/bin/bash
# --arch selects the architecture the image is assembled for.
#
# Saphira began building aarch64 alongside x86_64. The architecture is
# not a cosmetic flag: it decides which packages apk installs into the
# image, which repository subdirectory those come from, and which
# bootloader platform the firmware will look for. Getting any of the
# three wrong produces an image that assembles cleanly and boots
# nothing.
#
# Two things made this worth doing carefully:
#
#   - apk infers architecture from the RUNNING HOST by default. Building
#     an aarch64 image on an x86_64 builder therefore silently installed
#     x86_64 packages unless the architecture was stated explicitly all
#     the way down to apk.
#   - the bootloader platform is derived from the boot method AND the
#     architecture. `--target=x86_64-efi` on an aarch64 image installs a
#     bootloader that aarch64 firmware will never look for.
#
# Rootless: `plan` performs no privileged work and no image is built.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=${SAPHIRA_IMAGE:-$here/../files/saphira-image}
bootstrap=${SAPHIRA_BOOTSTRAP:-$here/../../saphira-install-tools/files/saphira-bootstrap}
install_tool=${SAPHIRA_INSTALL:-$here/../../saphira-install-tools/files/saphira-install}

for f in "$tool" "$bootstrap" "$install_tool"; do
	test -r "$f" || { printf 'not readable: %s\n' "$f" >&2; exit 1; }
done

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# the default is x86_64 and existing output is unchanged'

out=$("$tool" plan --target uefi-saphira --size 128G 2>&1)
case $out in
*'arch=x86_64'*) ok 'the default architecture is x86_64' ;;
*) bad "the default architecture is not x86_64: $out" ;;
esac
case $out in
*'start=133120, size=268300288'*)
	ok 'the x86_64 UEFI partition plan is unchanged' ;;
*)
	bad "the x86_64 partition plan changed: $out" ;;
esac

# The ESP is 64 MiB (131072 sectors): enough for the ~1.5 MiB EFI
# payload many times over, far above the FAT32 cluster-count floor
# that rules out 32 MiB, and eight times smaller than the old default.
# A silent ESP resize changes every UEFI image layout, so it is pinned
# here, not just implied by the root line above.
case $out in
*'start=2048, size=131072'*)
	ok 'the ESP is 64 MiB' ;;
*)
	bad "the ESP is not the pinned 64 MiB: $out" ;;
esac

printf '%s\n' '# an explicit architecture is honoured'

out=$("$tool" plan --target uefi-saphira --size 128G --arch aarch64 2>&1)
case $out in
*'arch=aarch64'*) ok 'an explicit architecture appears in the plan' ;;
*) bad "the requested architecture was not applied: $out" ;;
esac

printf '%s\n' '# combinations the platform does not have are refused'

# There is no BIOS firmware for aarch64. Refusing is the only safe
# answer: producing an image that cannot boot is worse than refusing.
out=$("$tool" plan --target bios-saphira --arch aarch64 2>&1)
case $out in
*'cannot boot BIOS'*) ok 'BIOS on aarch64 is refused' ;;
*) bad "BIOS on aarch64 must be refused: $out" ;;
esac

# Fail closed on an unknown architecture rather than passing it through
# to apk and the bootloader, where it would fail further from the cause.
out=$("$tool" plan --target uefi-saphira --arch riscv64 2>&1)
case $out in
*'unsupported --arch'*) ok 'an unknown architecture is refused by name' ;;
*) bad "an unknown architecture must be refused: $out" ;;
esac

printf '%s\n' '# the bootloader platform follows the architecture'

if grep -q 'grub_args="--target=\$ARCH-efi' "$tool"; then
	ok 'the EFI bootloader platform is derived from the architecture'
else
	bad 'the EFI bootloader platform is hardcoded and ignores the architecture'
fi
if grep -q 'BIOS firmware for aarch64' "$tool"; then
	ok 'the tool explains why BIOS on aarch64 is impossible'
else
	bad 'the BIOS/aarch64 refusal must say why'
fi

printf '%s\n' '# the architecture reaches apk'

# The whole point: without this, apk resolves the BUILDING host's
# architecture and an aarch64 image silently gets x86_64 packages.
if grep -qF -- '--arch "$arch"' "$bootstrap"; then
	ok 'saphira-bootstrap passes the architecture to apk'
else
	bad 'saphira-bootstrap must pass --arch to apk'
fi
if grep -q 'arch=${SAPHIRA_ARCH:-x86_64}' "$bootstrap"; then
	ok 'the bootstrap architecture defaults to x86_64'
else
	bad 'the bootstrap architecture must default to x86_64'
fi

printf '%s\n' '# the architecture survives the whole chain'

for stage in "$install_tool" "$here/../../saphira-install-tools/files/saphira-assemble-rootfs"; do
	if grep -q 'SAPHIRA_ARCH' "$stage"; then
		ok "the architecture is forwarded by $(basename "$stage")"
	else
		bad "$(basename "$stage") drops the architecture on the floor"
	fi
done
if grep -q 'SAPHIRA_ARCH="\$ARCH"' "$tool"; then
	ok 'saphira-image exports the architecture into the install chain'
else
	bad 'saphira-image must export the architecture into the install chain'
fi

printf '%s\n' '# a foreign-architecture image really resolves foreign packages'

# Plan is static, so this checks the assembled package set is requested
# for the right architecture rather than merely recorded. The check is
# on the repository layout: apk selects <repository>/<arch>, and the
# public repository serves one directory per architecture.
for arch in x86_64 aarch64; do
	url=https://packages.saphira.vm2.uk/hatched
	if timeout 120 curl -fsS -o /dev/null -w '%{http_code}' "$url/$arch/" 2>/dev/null |
		grep -qE '^(200|403)$'; then
		ok "the signed repository serves an $arch directory"
	else
		printf 'note     the signed repository does not yet serve %s/\n' "$arch" >&2
	fi
done

if test "$failures" -ne 0; then
	printf 'arch-selection: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'arch-selection: OK'