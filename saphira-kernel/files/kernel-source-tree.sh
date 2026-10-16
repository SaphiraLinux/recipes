#!/bin/sh
# kernel-source-tree.sh - staging and purity gates for saphira-kernel-source-*.
#
# Sourced by the saphira-kernel-source-<ver> recipe_install() and by
# saphira-packager/tests/kernel-source-tree.sh. Pure filesystem logic over
# explicit directory arguments (no builder globals), so the gates are
# unit-testable without extracting a kernel.
#
# THE INVARIANT
#
#     kernel build tree  !=  kernel source package input
#
# saphira-kernel-source-<ver> is built from a FRESH extraction of the verified
# upstream tarball plus the deliberate Saphira source patch. It never compiles
# anything, so there is no build tree in its workspace for build output to leak
# from. This file is the machine-checkable statement of that: the package is
# upstream source + intentional Saphira patches, and ZERO generated build state.
#
# WHY THIS FILE EXISTS (the r1 defect)
#
# The r1 recipes extracted the tarball into $SRC, ran `make olddefconfig &&
# make -j$(nproc)`, and then staged the payload from that same post-make tree
# via install_prepared_tree(). buildpkg-single runs recipe_build and
# recipe_install against one $SRC, so the "source package" was assembled from a
# used kernel build tree.
#
# install_prepared_tree() is a DENYLIST, and it only listed the names someone
# remembered to delete. The published saphira-kernel-source-7.2.2-1-r1.apk
# measured 353,120,683 bytes compressed, installed-size 1,713,546,224 and
# 82,890 paths, of which 3,417 were absent from the upstream tarball entirely.
# Its prune list did remove *.o/*.ko/*.cmd (those really are zero in the
# payload), which is exactly why the rest went unnoticed: the gate worked on
# the cases it named and stayed silent on everything else.
#
# Proof it was a build tree, not source:
#     usr/src/linux-7.2.2-saphira/Module.symvers
#     usr/src/linux-7.2.2-saphira/.config
#     usr/src/linux-7.2.2-saphira/vmlinux.unstripped
#     usr/src/linux-7.2.2-saphira/arch/x86/boot/bzImage
#     usr/src/linux-7.2.2-saphira/arch/x86/boot/compressed/vmlinux.bin
#     usr/src/linux-7.2.2-saphira/include/generated/...
#     usr/src/linux-7.2.2-saphira/include/config/...        (2,395 entries)
#     usr/src/linux-7.2.2-saphira/tools/objtool/fixdep    (built host tool)
#     usr/src/linux-7.2.2-saphira/scripts/sign-file        (built host tool)
#     usr/src/linux-7.2.2-saphira/lib/lib.a                (build-generated)
#     usr/src/linux-7.2.2-saphira/usr/gen_init_cpio        (built host tool)
#     usr/src/linux-7.2.2-saphira/.tmp_missing-syscalls    (build stamp)
#     ... and 834 modules.order install-time lists
#
# WHY A NEW FILE, NOT AN EDIT OF install-kernel-layout.sh
#
# install-kernel-layout.sh is sourced by the RUNTIME saphira-kernel recipe and
# its payload is a release gate (kernel-layout.sh). install_prepared_tree is
# still needed there by the disabled saphira-kernel-devel-* identities, so it
# stays exactly as it is. The source-package contract is a different contract
# and lives in its own file, where a change to it cannot move the runtime gate.
#
# FALSE-POSITIVE DISCIPLINE
#
# Every rule below was calibrated against the real verified tarball
# (linux-7.2.2.tar.xz, 101,060 entries) by diffing the contaminated r1 payload
# against it. Three things that LOOK like build output are upstream source and
# are therefore explicitly allowed, because a gate that rejects a correct
# package gets disabled instead of fixed:
#
#   usr/dummy-include/**      upstream ships these stub headers
#   tools/include/generated/**  upstream commits asm-offsets.h, cpucap-defs.h,
#                               sysreg-defs.h
#   certs/signing_key.x509    public key; only the PRIVATE .pem is forbidden
#
# Likewise the vmlinux rules are an ALLOWLIST of the eighteen upstream source
# basenames, because "vmlinux" alone is ambiguous: vmlinux.lds.S is source you
# read and vmlinux.unstripped is a 200 MB link artefact.
#
# SCOPE OF THIS GATE, HONESTLY STATED
#
# Against the r1 payload this catches 3,358 of the 3,410 build-added paths
# with zero false positives on the pristine tree. The remaining 52 are
# generated .c/.h/.s TABLE files (lib/crc/crc32table.h,
# crypto/*/pkcs7.asn1.c, drivers/tty/vt/defkeymap.c, kernel/bounds.s,
# scripts/kconfig/parser.tab.c and friends). Those cannot be matched by
# pattern without either rejecting real source or needing the tarball,
# because upstream ships tens of thousands of .c and .h files.
#
# So this gate is the TRIPWIRE that runs inside the build and names the
# defect, not the exhaustive proof. Exhaustive coverage is
# saphira-packager/tests/kernel-source-purity.sh, which diffs the published
# payload path set against the verified upstream tarball and fails on ANY
# path the tarball does not contain. Two layers, because one is cheap enough
# to run on every build and the other needs the archive.

kst_die()
{
	printf 'kernel-source-tree: %s\n' "$*" >&2
	return 1
}

# Upstream source basenames that legitimately contain "vmlinux". Anything else
# named vmlinux* in a source tree is linked output. Verified against the
# linux-7.2.2 tarball basename set (101,060 entries). Note this list does NOT
# contain a bare `vmlinux`, because the one upstream bare vmlinux is legal by
# PATH (the BTF skeleton) and is handled in kst_path_forbidden instead.
kst_vmlinux_source_name()
{
	case $1 in
	Makefile.vmlinux | Makefile.vmlinux_a | Makefile.vmlinux_o | \
	extract-vmlinux | link-vmlinux.sh | test_vmlinux.c | \
	vmlinux-gdb.py | vmlinux-kallsyms.c | vmlinux.c | vmlinux.h | \
	vmlinux.its.S | vmlinux.lds.S | vmlinux.lds.h | vmlinux.scr | \
	vmlinux-xip.lds.S | vmlinux-nommu.lds | vmlinux-std.lds | \
	vmlinux-sun3.lds)
		return 0
		;;
	esac
	return 1
}

# kst_path_forbidden RELPATH - true when RELPATH (tree-relative) is build state.
kst_path_forbidden()
{
	_rel=$1
	_base=${_rel##*/}

	# 1. Compiled output and per-file build records. No upstream source file
	#    in any vendored kernel line carries one of these extensions; the
	#    tarball basename scan returned zero for every one of them, including
	#    the compressed and linker-scratch forms the compressed payload uses
	#    (vmlinux.bin.bz2, vmlinux.relocs, purgatory.chk, purgatory.ro).
	case $_base in
	*.o | *.ko | *.a | *.so | *.so.dbg | *.cmd | *.mod | *.mod.c | \
		*.symtypes | *.dwo | *.gcno | *.su | *.bin | *.elf | *.cpio | \
		*.bz2 | *.gz | *.relocs | *.chk | *.ro | *.o.d)
		printf 'compiled object/archive: %s\n' "$_rel"
		return 0
		;;
	esac

	# 1b. Whole-file build products with no distinguishing extension.
	#    Scoped to the four kheaders OUTPUTS: kernel/kheaders.c is the
	#    upstream source that produces them and must stay, and the same is
	#    true of the genksyms script, so neither is matched by bare name.
	case $_rel in
	kernel/kheaders-objlist | kernel/kheaders-srclist | \
		kernel/kheaders.md5 | kernel/kheaders_data.tar.xz | \
		kernel/config_data | kernel/config_data.gz)
		printf 'kheaders/config build product: %s\n' "$_rel"
		return 0
		;;
	esac

	# 2. Configuration and exported-symbol state. A source package has no
	#    configuration: shipping .config is what made this package claim to
	#    be a build tree for external modules.
	case $_base in
	.config | .config.old | Module.symvers | System.map)
		printf 'build configuration/symbol state: %s\n' "$_rel"
		return 0
		;;
	modules.order | modules.builtin | modules.builtin.modinfo)
		printf 'install-time module list: %s\n' "$_rel"
		return 0
		;;
	esac

	# 3. Linked kernel images. "vmlinux" is ambiguous, so this is decided in
	#    two stages: the committed BTF skeleton is allowed by exact path,
	#    then everything else carrying the name must be one of the upstream
	#    SOURCE basenames. Getting this wrong in either direction is bad --
	#    too strict rejects a correct package and gets the gate switched off;
	#    too loose ships vmlinux.unstripped and the compressed payload, which
	#    is most of what r1 actually published. So both stages are explicit.
	case $_rel in
	tools/perf/util/bpf_skel/vmlinux)
		return 1
		;;
	esac
	case $_base in
	*vmlinux*)
		if kst_vmlinux_source_name "$_base"; then
			return 1
		fi
		printf 'generated vmlinux artefact: %s\n' "$_rel"
		return 0
		;;
	esac

	case $_base in
	bzImage | vmlinuz | Image | zImage)
		printf 'bootable kernel image: %s\n' "$_rel"
		return 0
		;;
	esac

	# 4. Built host tools. These are compiled binaries that live next to
	#    their .c source and therefore have no distinguishing extension:
	#    scripts/mod/modpost, scripts/sign-file, tools/objtool/fixdep.
	#    Upstream ships modpost.c, sign-file.c, fixdep.c and never the bare
	#    names, so a bare-name match cannot hit real source. Two names --
	#    objtool and mdp -- ARE upstream basenames somewhere in the tree
	#    (their Makefiles and .c inputs), so they are matched by PATH rather
	#    than by basename and the bare name is left alone.
	case $_base in
	fixdep | modpost | sign-file | mkpiggy | mkcpustr | mk_elfconfig | \
		gen_init_cpio | kallsyms | recordmcount | sortextable | \
		setsync | sorttable | fdtoverlay | unpack_too | dt_to_bindir | \
		rm-edata | lib.a | setup.bin | setup.elf | vdso64.so | \
		vdso64-image.c | voffset.h | zoffset.h | inat-tables.c | \
		cpustr.h | setup-obj | conf | llvm-objtool | extract-cert | \
		asn1_compiler | conmakehash | genheaders | tracepoint-update | \
		vdso2c | relocs | gen_crc32table | gen_crc64table | \
		x509_certificate_list | embedconfig | kheaders | x509)
		printf 'built host tool: %s\n' "$_rel"
		return 0
		;;
	esac
	case $_rel in
	tools/objtool/objtool | scripts/selinux/mdp/mdp)
		printf 'built host tool: %s\n' "$_rel"
		return 0
		;;
	esac

	# 5. Build stamps and scratch left by the top-level make.
	case $_base in
	.tmp_* | .vmlinux.export.c | .version | .checked-atomic-*)
		printf 'build stamp/scratch: %s\n' "$_rel"
		return 0
		;;
	*.orig | *.rej | *~)
		printf 'patch residue: %s\n' "$_rel"
		return 0
		;;
	utsversion-tmp.h)
		printf 'generated build header: %s\n' "$_rel"
		return 0
		;;
	esac
	case $_rel in
	init/utsversion-tmp.h | scripts/module.lds | certs/regdb | certs/regdb/*)
		printf 'generated build artefact: %s\n' "$_rel"
		return 0
		;;
	esac

	# 6. Compiler-derived include trees. Scoped deliberately:
	#    include/generated/ and include/config/ are the kernel build's own
	#    output, and arch/*/include/generated/ is per-arch output.
	#    tools/include/generated/ is NOT forbidden: upstream commits
	#    asm-offsets.h, cpucap-defs.h and sysreg-defs.h there.
	case $_rel in
	include/generated | include/generated/* | \
		include/config | include/config/* | \
		arch/*/include/generated | arch/*/include/generated/*)
		printf 'generated include tree: %s\n' "$_rel"
		return 0
		;;
	esac

	# 7. Signing material. Only the PRIVATE keys are forbidden; the public
	#    signing_key.x509 and the regdb CA certificates are source.
	case $_rel in
	certs/*.pem | certs/*/*.pem)
		printf 'module signing key material: %s\n' "$_rel"
		return 0
		;;
	esac

	return 1
}

# check_source_tree_pure ROOT - fail if ROOT is anything other than upstream
# source plus intentional Saphira patches. Prints every offender (bounded) and
# a count, so a failure names the paths rather than asserting a verdict.
check_source_tree_pure()
{
	[ "$#" -eq 1 ] || { kst_die "usage: check_source_tree_pure ROOT"; return 1; }
	root=$1
	[ -d "$root" ] || { kst_die "source tree missing: $root"; return 1; }
	[ -f "$root/Makefile" ] || { kst_die "no Makefile in $root"; return 1; }

	# A source tree legitimately contains no newlines in any path name
	# (upstream forbids them), so newline-delimited find output is safe here
	# and keeps this usable from /bin/sh without read -d.
	#
	# Directories are walked as well as files. An earlier revision walked
	# files only, and that missed every generated DIRECTORY -- include/
	# generated, include/config, arch/x86/include/generated, certs/regdb,
	# tools/objtool/lib -- because in a build tree those hold generated
	# files that are themselves caught, so the omission only showed up as
	# 20 unaccounted-for paths in the payload diff. Their mere presence is
	# the defect: a source tree must not have them at all.
	offenders=$(
		find "$root" \( -type f -o -type l -o -type d \) -print 2>/dev/null |
		while IFS= read -r p; do
			# `|| :` is load-bearing, not defensive noise. kst_path_forbidden
			# returns 1 for a clean path, and buildpkg-single runs recipes
			# under `set -e`. A bare call inside this loop therefore aborts
			# the recipe on the FIRST clean file, so the gate reported
			# nothing and the build failed with no diagnostic. That bug was
			# invisible to the unit suite because it called the gate from an
			# `if`, and set -e is disabled in condition context -- so the
			# suite exercised a different execution path from the build.
			kst_path_forbidden "${p#"$root"/}" || :
		done
	)
	if [ -z "$offenders" ]; then
		n=$(find "$root" \( -type f -o -type l \) 2>/dev/null | wc -l)
		printf 'kernel-source-tree: %s OK (%s files, upstream source + Saphira patches, no build state)\n' \
			"$root" "$n"
		return 0
	fi
	count=$(printf '%s\n' "$offenders" | wc -l)
	printf 'kernel-source-tree: %s CONTAMINATED (%s build artefacts)\n' "$root" "$count" >&2
	# Bounded sample. head closing the pipe early sends printf SIGPIPE, and
	# under `set -o pipefail` that surfaces as 141 instead of the intended 1,
	# which turns "the gate found contamination" into "the gate crashed".
	# A real contaminated tree has thousands of offenders, so this is the
	# normal path, not an edge case.
	printf '%s\n' "$offenders" | head -40 >&2 || :
	# `|| :` for the same reason: a false test would otherwise abort under
	# set -e before the intended non-zero return below.
	[ "$count" -gt 40 ] && printf '  ... and %s more\n' "$((count - 40))" >&2 || :
	return 1
}

# install_clean_source_tree SRCDIR DESTDIR - stage a kernel SOURCE tree.
#
# SRCDIR must already be a fresh extraction of the verified upstream tarball
# plus the Saphira source patch: no make, no .config, no cert material, no
# generated state. It is verified BEFORE the copy, so a contaminated input
# fails the build without ever reaching the payload, and DESTDIR is verified
# AGAIN afterwards so the copy itself is proven to have introduced nothing.
#
# The pre/post pair is deliberate. A single post-copy check would only say
# "the payload is clean", which is the symptom; checking the input too says
# WHY, and names the build tree if one was passed in by mistake.
install_clean_source_tree()
{
	[ "$#" -eq 2 ] || { kst_die "usage: install_clean_source_tree SRCDIR DESTDIR"; return 1; }
	src=$1
	dest=$2
	[ -d "$src" ] || { kst_die "source tree missing: $src"; return 1; }
	[ -f "$src/Makefile" ] || { kst_die "no Makefile in $src"; return 1; }

	check_source_tree_pure "$src" >/dev/null ||
		{ kst_die "refusing to stage a contaminated source tree: $src"; return 1; }

	mkdir -p "$dest" || { kst_die "cannot create $dest"; return 1; }
	# cp -a: in-tree symlinks are part of the source (arch/*/Kbuild links,
	# Documentation cross-links) and upstream modes/times must survive. The
	# payload establishes its own ownership; makepkg handles that.
	cp -a "$src/." "$dest/" || { kst_die "tree copy failed: $src -> $dest"; return 1; }

	check_source_tree_pure "$dest" >/dev/null ||
		{ kst_die "staged tree is contaminated: $dest"; return 1; }
	check_source_tree_pure "$dest"
}