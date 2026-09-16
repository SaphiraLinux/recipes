#!/bin/sh

# Kernel installed-layout regression: the module-tree relationship
# without compiling a kernel. Exercises
# saphira-kernel/files/install-kernel-layout.sh against a fixture tree
# (fake Makefile with a kernelrelease target, prepared-state files,
# build-time junk, a leaked signing key) and a fixture PKGDEST seeded
# with the historical bug (build/source symlinks into /build).
#
# usage: kernel-layout.sh INSTALL-KERNEL-LAYOUT-SH

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s INSTALL-KERNEL-LAYOUT-SH\n' "$0" >&2
	exit 1
}

layout_sh=$1
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-kernel-layout-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

# shellcheck disable=SC1090
. "$layout_sh"

# Fixture source tree: prepared state plus everything the installer
# must prune (objects, images, leaked key, userspace bulk, docs).
mkdir -p "$test_root/faketree/include/generated" \
	"$test_root/faketree/arch/x86/include/generated/asm" \
	"$test_root/faketree/scripts/mod" "$test_root/faketree/certs" \
	"$test_root/faketree/drivers/net" "$test_root/faketree/tools/perf" \
	"$test_root/faketree/tools/objtool" "$test_root/faketree/tools/include" \
	"$test_root/faketree/Documentation" "$test_root/faketree/.tmp_versions"
printf '%s\n' 'kernelrelease:' '	@echo 7.2.2' > "$test_root/faketree/Makefile"
printf '%s\n' 'CONFIG_TEST=y' > "$test_root/faketree/.config"
printf '%s\n' '0x00000000	symbol	testmod	EXPORT_SYMBOL' > "$test_root/faketree/Module.symvers"
printf '%s\n' '#define AUTOCONF_INCLUDED' > "$test_root/faketree/include/generated/autoconf.h"
printf '%s\n' '#define __NR_test 999' > "$test_root/faketree/arch/x86/include/generated/asm/unistd_64.h"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_root/faketree/scripts/mod/modpost"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_root/faketree/scripts/sign-file"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_root/faketree/tools/objtool/objtool"
chmod 755 "$test_root/faketree/scripts/mod/modpost" \
	"$test_root/faketree/scripts/sign-file" "$test_root/faketree/tools/objtool/objtool"
printf '%s\n' 'object' > "$test_root/faketree/drivers/net/driver.o"
printf '%s\n' 'cmd' > "$test_root/faketree/drivers/net/driver.o.cmd"
printf '%s\n' 'module' > "$test_root/faketree/drivers/net/driver.ko"
printf '%s\n' 'tmp' > "$test_root/faketree/.tmp_versions/driver.mod"
printf '%s\n' 'image' > "$test_root/faketree/vmlinux"
printf '%s\n' 'map' > "$test_root/faketree/System.map"
printf '%s\n' 'PRIVATE KEY (must never ship)' > "$test_root/faketree/certs/module-signing.pem"
printf '%s\n' 'perf' > "$test_root/faketree/tools/perf/perf"
printf '%s\n' 'doc' > "$test_root/faketree/Documentation/README"
printf '%s\n' 'old' > "$test_root/faketree/.config.old"

# Fixture PKGDEST with the historical bug: upstream modules_install
# baked absolute constructor paths into build and source.
mkdir -p "$test_root/fakepkg/lib/modules/7.2.2/kernel"
ln -s /build/saphira-kernel/source/linux-7.2.2 "$test_root/fakepkg/lib/modules/7.2.2/build"
ln -s /build/saphira-kernel/source/linux-7.2.2 "$test_root/fakepkg/lib/modules/7.2.2/source"

krel=$(kernel_layout_release "$test_root/faketree")
[ "$krel" = "7.2.2" ] || { printf '%s\n' "kernelrelease derivation broke: $krel" >&2; exit 1; }

install_prepared_tree "$test_root/faketree" "$test_root/fakepkg/usr/src/linux-7.2.2-saphira"
tree=$test_root/fakepkg/usr/src/linux-7.2.2-saphira

# Prune proof: intermediates, images, leaked key, bulk and docs are
# gone; source, prepared state and the objtool chain survive.
for gone in drivers/net/driver.o drivers/net/driver.o.cmd \
	drivers/net/driver.ko .tmp_versions vmlinux System.map \
	certs/module-signing.pem tools/perf Documentation .config.old; do
	[ ! -e "$tree/$gone" ] || { printf '%s\n' "prune missed: $gone" >&2; exit 1; }
done
for kept in Makefile .config Module.symvers include/generated/autoconf.h \
	arch/x86/include/generated/asm/unistd_64.h tools/objtool/objtool tools/include; do
	[ -e "$tree/$kept" ] || { printf '%s\n' "prune ate required file: $kept" >&2; exit 1; }
done
[ -x "$tree/scripts/mod/modpost" ] || { printf '%s\n' 'modpost lost exec bit' >&2; exit 1; }
[ -x "$tree/scripts/sign-file" ] || { printf '%s\n' 'sign-file lost exec bit' >&2; exit 1; }

install_module_build_link "$test_root/fakepkg" 7.2.2 linux-7.2.2-saphira
check_module_layout "$test_root/fakepkg" 7.2.2 linux-7.2.2-saphira 7.2.2

# Negative: the floating convenience link is not a valid build target.
ln -sfn /usr/src/linux "$test_root/fakepkg/lib/modules/7.2.2/build"
if check_module_layout "$test_root/fakepkg" 7.2.2 linux-7.2.2-saphira 7.2.2 \
	> "$test_root/floating.out" 2> "$test_root/floating.err"; then
	printf '%s\n' 'floating /usr/src/linux build target unexpectedly verified' >&2
	exit 1
fi
grep 'want /usr/src/linux-7.2.2-saphira' "$test_root/floating.err" >/dev/null

# Negative: any installed symlink into /build fails the check, even
# with a correct build link (generic constructor-leak scan).
ln -sfn /usr/src/linux-7.2.2-saphira "$test_root/fakepkg/lib/modules/7.2.2/build"
mkdir -p "$test_root/fakepkg/usr/bin"
ln -s /build/bzip2/pkg/usr/bin/bzgrep "$test_root/fakepkg/usr/bin/bzfgrep"
if check_module_layout "$test_root/fakepkg" 7.2.2 linux-7.2.2-saphira 7.2.2 \
	> "$test_root/releak.out" 2> "$test_root/releak.err"; then
	printf '%s\n' '/build leak unexpectedly verified' >&2
	exit 1
fi
grep 'point into /build' "$test_root/releak.err" >/dev/null
rm "$test_root/fakepkg/usr/bin/bzfgrep"

# Negative: a source symlink must not exist.
ln -sfn /usr/src/linux-7.2.2-saphira "$test_root/fakepkg/lib/modules/7.2.2/build"
ln -s /usr/src/linux-7.2.2-saphira "$test_root/fakepkg/lib/modules/7.2.2/source"
if check_module_layout "$test_root/fakepkg" 7.2.2 linux-7.2.2-saphira 7.2.2 \
	> "$test_root/source.out" 2> "$test_root/source.err"; then
	printf '%s\n' 'source symlink unexpectedly verified' >&2
	exit 1
fi
grep 'must not exist' "$test_root/source.err" >/dev/null

printf '%s\n' 'kernel installed-layout (versioned build link, prepared-tree prune, key hygiene, /build ban): OK'
