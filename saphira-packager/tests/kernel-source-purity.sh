#!/bin/sh

# saphira-kernel-source-* payload purity and provenance gate.
#
# usage: kernel-source-purity.sh SOURCE-APK [PRISTINE-TARBALL]
#
# THE DEFECT THIS EXISTS TO CATCH
#
#     kernel build tree  !=  kernel source package input
#
# saphira-kernel-source-<ver>-1-r1 was assembled from a USED KERNEL BUILD TREE.
# buildpkg-single runs recipe_build and recipe_install against one $SRC; r1 ran
# `make olddefconfig && make -j$(nproc)` there and then copied that same
# directory into the payload. install_prepared_tree() pruned a DENYLIST of the
# names somebody remembered, and everything it did not name shipped:
#
#     Module.symvers   .config                vmlinux.unstripped
#     arch/x86/boot/bzImage                    boot/compressed/vmlinux.bin*
#     include/config/  (2,395 entries)        include/generated/
#     scripts/sign-file  scripts/mod/modpost  tools/objtool/fixdep
#     lib/lib.a  (x4)   usr/gen_init_cpio     modules.order  (834 entries)
#     .tmp_missing-syscalls
#
# The published saphira-kernel-source-7.2.2-1-r1.apk measured 353,120,683 bytes
# compressed, installed-size 1,713,546,224 and 82,890 payload paths, of which
# 3,410 were absent from the upstream tarball entirely.
#
# WHY THIS IS A RELEASE GATE AND NOT A NOTE
#
# The kernel has already shipped this class of regression twice: r7-r9 grew the
# runtime kernel from 32 MiB to 600 MiB compressed and ~70 MiB to ~2.4 GiB
# installed, and the source packages were never smaller than the kernel they
# describe. Neither was visible in a build log. The only place it shows up is a
# comparison against what the archive actually contains -- which is what check 1
# below does, and it is the reason the tarball is worth passing in.
#
# CHECK 1 IS THE EXHAUSTIVE ONE
#
# It diffs the published payload's path set against the verified upstream
# tarball. Anything the tarball does not contain is, by definition, not
# upstream source, so it cannot be defended as a packaging choice. That catches
# the whole class, including the generated .c/.h/.s table files (lib/crc/
# crc32table.h, crypto/*/pkcs7.asn1.c, drivers/tty/vt/defkeymap.c,
# scripts/kconfig/parser.tab.c and ~50 more) that no name-based rule can catch
# without also rejecting real source, because upstream ships tens of thousands
# of .c and .h files.
#
# Checks 2-8 then restate the specific things the task names, so a failure says
# WHICH defect it is rather than only that the diff was non-empty.
#
# vmlinux NEEDS AN ALLOWLIST, NOT A BLACKLIST
#
# "vmlinux" is ambiguous. vmlinux.lds.S, vmlinux.lds.h, vmlinux.its.S,
# vmlinux.scr, vmlinux.h, vmlinux.c, vmlinux-gdb.py, extract-vmlinux and
# link-vmlinux.sh are source you read. vmlinux, vmlinux.unstripped,
# vmlinux.bin and vmlinux.bin.bz2 are link output, and between them they are
# most of what r1 published. A blanket "no vmlinux" rule rejects a correct
# package; the gate below therefore forbids the GENERATED basenames and
# explicitly allows the upstream source ones.

set -eu

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
	printf 'usage: %s SOURCE-APK [PRISTINE-TARBALL]\n' "$0" >&2
	printf '  SOURCE-APK       the built saphira-kernel-source-<ver> APK\n' >&2
	printf '  PRISTINE-TARBALL the verified upstream linux-<ver>.tar.{xz,gz} it claims\n' >&2
	printf '                   to come from; enables the exhaustive diff (check 1)\n' >&2
	exit 1
}
apk_file=$1
tarball=${2-}
[ -f "$apk_file" ] || { printf 'no such file: %s\n' "$apk_file" >&2; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# adbdump gives the payload tree with per-file sizes, so this reads the package
# as it will actually be installed rather than as it was staged.
dump=$(apk adbdump "$apk_file" 2>/dev/null) || {
	printf 'apk adbdump failed on %s\n' "$apk_file" >&2
	exit 1
}

printf '  package: %s (%s bytes)\n' "$(basename "$apk_file")" "$(stat -c %s "$apk_file")"

# The adbdump payload tree is NESTED (paths: -> dirs:/files: -> - name:), so a
# flat grep is meaningless and an awk that assumed a flat shape silently
# reported 0 for r7, which shipped 77,655 /usr/src files. Reconstruct the real
# path set with an indent stack, which is what kernel-release-size.sh does too.
payload_list() {
	printf '%s\n' "$dump" | python3 -c '
import sys
root = sys.argv[1].rstrip("/")
stack = []
lines = sys.stdin.read().split("\n")
i = 0
while i < len(lines):
    ln = lines[i]
    i += 1
    if not ln.startswith(" "):
        continue
    b = ln.strip()
    ind = len(ln) - len(b)
    if not b.startswith("- name: "):
        continue
    nm = b[8:]
    if nm == "|":
        # apk adbdump marks a symlink entry with a bare "|" name and puts the
        # real path on the following line. That real path is the FRAME the
        # entry occupies: it has children (files:/dirs:) in this tree, so the
        # paths that follow belong to it. Treating "|" as the frame instead
        # empties the stack and orphans every child, which is how a correct
        # package ends up reported as carrying a thousand stray basenames.
        while i < len(lines) and not lines[i].strip():
            i += 1
        real = lines[i].strip() if i < len(lines) else ""
        i += 1
        for k in [k for k in stack if k[0] >= ind]:
            stack.pop()
        if not real:
            continue
        full = real
    else:
        for k in [k for k in stack if k[0] >= ind]:
            stack.pop()
        full = (stack[-1][1] + "/" if stack else "") + nm
    stack.append((ind, full))
    if root and not full.startswith(root):
        continue
    print(full)
sys.exit(0)' "$1"
}

# The single tree this package owns. adbdump emits directory names WITHOUT a
# trailing slash, so this matches the bare path rather than a slash-terminated
# one.
tree=$(payload_list '' | sed -n 's|^\(usr/src/[^/]*\)$|\1|p' | head -1)
if [ -z "$tree" ]; then
	no "no /usr/src/<kernel> tree in the payload at all - a source package must ship its tree"
	printf 'kernel source purity: %d passed, %d failed\n' "$pass" "$fail"
	exit 1
fi
ok "source tree root is /$tree"

paths=$(payload_list "$tree")

# ==================================================== 1. exhaustive path diff
# Everything the upstream archive does not contain is not upstream source.
# This is the check that has no blind spot: it needs no rule, because the
# archive is the definition.
if [ -n "$tarball" ]; then
	[ -f "$tarball" ] || { printf 'no such tarball: %s\n' "$tarball" >&2; exit 1; }
	base=$(basename "$tarball")
	ref=$(mktemp)
	got=$(mktemp)
	trap 'rm -f "$ref" "$got"' EXIT
	# Strip the archive's single top-level directory so both sides are
	# tree-relative. tar -t emits directories with a trailing slash; the
	# payload dump does not, so both are normalised.
	tar -tf "$tarball" | sed 's|^[^/]*/||; s|/$||' | grep -v '^$' | sort -u > "$ref"
	# Every payload path relative to the tree root, directories included.
	# The tree root itself becomes an empty line after stripping and must be
	# dropped, or the diff reports the root as a path "not in the tarball".
	printf '%s\n' "$paths" | sed "s|^$tree/*||" | grep -v '^$' | sort -u > "$got"
	extra=$(comm -13 "$ref" "$got" | wc -l)
	missing=$(comm -23 "$ref" "$got" | wc -l)
	if [ "$extra" -eq 0 ]; then
		ok "every payload path exists in $base (no build-derived paths)"
	else
		no "$extra payload paths are NOT in $base - they are build output, not source"
		comm -13 "$ref" "$got" | head -25 | sed 's/^/         /' >&2 || true
		[ "$extra" -gt 25 ] && printf '         ... and %s more\n' "$((extra - 25))" >&2 || true
	fi
	# Missing paths are only a failure if they are files. A tarball that omits
	# empty directories is normal; report the count either way.
	if [ "$missing" -eq 0 ]; then
		ok "payload carries all $base entries"
	else
		printf '  note payload omits %s archive paths (empty dirs or pruned docs)\n' "$missing"
	fi
else
	printf '  note no tarball given: the exhaustive path diff (check 1) was SKIPPED\n'
	printf '       the remaining checks are name-based and cannot see every class\n'
fi

# ================================== 2. the specifically named build artefacts
# Each of these is a defect in its own right, so each is asserted by name.
forbidden_count() {
	printf '%s\n' "$paths" | awk -v pat="$1" '
		BEGIN { n = 0 }
		{
			b = $0
			sub(/.*\//, "", b)
			if (b ~ pat) { n++ }
		}
		END { print n }'
}

# show PATHLIST LABEL - print a bounded sample without tripping set -e.
# head closing a pipe early sends the writer SIGPIPE, and under set -e that is
# a non-zero status, so a diagnostic would abort the suite with exit 141. The
# sample is a diagnostic, never the verdict, so it must not be able to fail.
show()
{
	printf '%s\n' "$1" | head -10 | sed 's/^/         /' >&2 || true
}

check_none() {
	_label=$1
	_pattern=$2
	_n=$(forbidden_count "$_pattern")
	if [ "$_n" -eq 0 ]; then
		ok "payload contains no $_label"
	else
		no "payload contains $_n $_label"
		show "$(printf '%s\n' "$paths" | awk -v pat="$_pattern" '
			{ b=$0; sub(/.*\//,"",b); if (b ~ pat) print $0 }')"
	fi
}

# Module.symvers: the single clearest proof of a build tree. A source package
# has no exported symbols; only a compiled kernel produces this file.
check_none "Module.symvers" '^Module\.symvers$'

# .config: a source package ships no configuration. This is what made r1 claim
# to be an external-module build tree.
check_none ".config" '^\.config$'

# vmlinux family, as ALLOWED upstream source names minus everything generated.
# Checked separately from check 1 so the failure names the defect.
#
# tools/perf/util/bpf_skel/vmlinux is the committed BTF skeleton and is allowed
# by exact path: it is the one place upstream ships a bare `vmlinux`, and
# forbidding it would reject a correct package -- which gets the gate switched
# off rather than fixed. The allowlist is applied to everything else.
vmlinux_bad=$(printf '%s\n' "$paths" | awk '
	{
		if ($0 ~ /\/tools\/perf\/util\/bpf_skel\/vmlinux$/) next
		b = $0
		sub(/.*\//, "", b)
		if (b !~ /vmlinux/) next
		if (b ~ /^(Makefile\.vmlinux(_a|_o)?|extract-vmlinux|link-vmlinux\.sh|test_vmlinux\.c|vmlinux-gdb\.py|vmlinux-kallsyms\.c|vmlinux\.c|vmlinux\.h|vmlinux\.its\.S|vmlinux\.lds\.S|vmlinux\.lds\.h|vmlinux\.scr|vmlinux-xip\.lds\.S|vmlinux-nommu\.lds|vmlinux-std\.lds|vmlinux-sun3\.lds)$/) next
		print
	}')
nbad=$(printf '%s\n' "$vmlinux_bad" | grep -c . || true)
if [ "$nbad" -eq 0 ]; then
	ok "payload contains no generated vmlinux* artefact (upstream vmlinux source names allowed)"
else
	no "payload contains $nbad generated vmlinux* artefacts"
	show "$vmlinux_bad"
fi

# include/generated and include/config: compiler-derived headers. Scoped
# deliberately -- tools/include/generated/ is upstream-committed
# (asm-offsets.h, cpucap-defs.h, sysreg-defs.h) and must NOT be flagged.
# $paths entries are absolute-in-payload (usr/src/<tree>/...), so the tree root
# is stripped first: a single sub() on /^[^/]*\// is NOT enough, it would only
# remove usr/ and leave src/<tree>/... unmatched.
gen_inc=$(printf '%s\n' "$paths" | awk -v t="$tree" '
	{
		p = $0
		sub(/^[^/]+\//, "", p)       # usr/
		sub(/^[^/]+\//, "", p)       # src/
		sub(/^[^/]+\//, "", p)       # <tree>/
		if (p ~ /^include\/generated(\/|$)/) print $0
		else if (p ~ /^include\/config(\/|$)/) print $0
		else if (p ~ /^arch\/[^/]*\/include\/generated(\/|$)/) print $0
	}')
ngen=$(printf '%s\n' "$gen_inc" | grep -c . || true)
if [ "$ngen" -eq 0 ]; then
	ok "payload contains no include/generated, include/config or arch/*/include/generated"
else
	no "payload contains $ngen generated include-tree entries"
	show "$gen_inc"
fi

# Compiled objects, modules, archives and per-file command records.
check_none "*.o object" '\.o$'
check_none "*.ko module" '\.ko$'
check_none "*.a archive" '\.a$'
check_none "*.cmd command record" '\.cmd$'

# Bootable images: a source package never ships the kernel it describes.
check_none "bzImage/vmlinuz bootable image" '^(bzImage|vmlinuz|zImage|Image)$'

# install-time module lists and build stamps
check_none "modules.order/builtin list" '^modules\.(order|builtin|builtin\.modinfo)$'
check_none ".tmp_* build stamp" '^\.tmp'

# Module signing key material. The PUBLIC signing_key.x509 and the regdb CA
# certificates are source; only the PRIVATE .pem is forbidden.
#
# Scope: certs/*.pem, which is where the kernel build puts its signing key and
# what r1 staged. A blanket ".pem anywhere" rule is wrong -- upstream ships
# tools/testing/selftests/sgx/sign_key.pem, a keypair self-test FIXTURE, and
# forbidding it would reject a correct package. Private key material that a
# source tree must never carry is under certs/; a selftest fixture under
# tools/testing/ is upstream content.
pem=$(printf '%s\n' "$paths" | awk '
	{
		p = $0
		sub(/^[^/]+\//, "", p); sub(/^[^/]+\//, "", p); sub(/^[^/]+\//, "", p)
		if (p ~ /^certs\/.*\.pem$/) print $0
	}')
npem=$(printf '%s\n' "$pem" | grep -c . || true)
if [ "$npem" -eq 0 ]; then
	ok "payload contains no key material (.pem)"
else
	no "payload contains $npem .pem key files"
	show "$pem"
fi

# ================================================= 3. installed-size sanity
# Not a hard ceiling: shipping kernel source is inherently large. This is a
# tripwire that fires only if build state reappears, and it is set from the
# measured r1 figure so the regression is caught even if every name-based check
# above were somehow satisfied.
# r1 measured installed-size 1,713,546,224 on 7.2.2 with 3,410 build-derived
# paths. A pristine 7.2.2 tree is ~1.1 GB. Anything above the r1 number means
# the payload got BIGGER than the artefact this gate exists to prevent.
installed=$(printf '%s\n' "$dump" | awk '/installed-size:/ {print $2; exit}')
[ -n "$installed" ] || { printf 'could not read installed-size\n' >&2; exit 1; }
if [ "$installed" -lt 1713546224 ]; then
	ok "installed-size $installed is below the contaminated r1 figure (1713546224)"
else
	no "installed-size $installed is at or above the contaminated r1 figure (1713546224)"
fi

# ================================================ 4. payload completeness
# A source package that ships 10 files is broken too, and would satisfy every
# forbidden-artifact check above. The tree must be substantial.
nfiles=$(printf '%s\n' "$paths" | grep -c . || true)
if [ "$nfiles" -gt 50000 ]; then
	ok "payload carries $nfiles paths (a full kernel source tree)"
else
	no "payload carries only $nfiles paths - a kernel source tree has >50,000 files"
fi

# Everything must live under the one intended /usr/src location: no second
# copy, and nothing outside it. usr and usr/src are the parent directories of
# that location and are not "outside" it.
outside=$(payload_list '' | grep -v "^$tree\(/\|$\)" | grep -v '^usr$' | grep -v '^usr/src$' || true)
if [ -z "$outside" ]; then
	ok "every payload path is under /$tree"
else
	no "payload carries $(printf '%s\n' "$outside" | wc -l) paths outside /$tree"
	show "$outside"
fi

printf 'kernel source purity: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]