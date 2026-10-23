#!/bin/sh

# Boot init contract: static assertions that the bootloader never names the
# init implementation and no merged-usr PID 1 path exists anywhere in the
# tree (SEV1 2026-10-22: packaged init=/usr/lib/systemd/systemd reached
# Egg's live grub.cfg through the kernel upgrade hook and panicked the
# machine - an explicit init= never falls back).
#
# Contract (see RECIPE_RULES.md "Boot init contract"):
# - /sbin/init is the sole canonical PID 1 entry point, owned by the
#   installed init system (openrc or systemd). Nothing else selects init.
# - Packaged bootloader defaults carry no init= token (an operator's
#   explicit --kernel-arg at image build time is their own runtime
#   override, not a packaged default).
# - /usr/sbin/init must never exist and is never referenced as an init
#   path (lxc's distinctly-named usr/sbin/init.lxc helper is not init).
# - sbin/init is never created as a symlink by a recipe.
#
# usage: init-contract.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

fail() {
	printf '%s\n' "init-contract: $*" >&2
	exit 1
}

# --- A. no init= token in any packaged bootloader default ---------------
#
# Covers default-grub conffiles, grub.cfg templates, and kernel hook
# scripts (which regenerate grub.cfg and must not inject arguments).

for grubfile in \
	"$source_root"/*/files/default-grub \
	"$source_root"/*/files/grub.cfg \
	"$source_root"/*/files/hooks-grub-mkconfig \
	"$source_root"/*/files/installkernel; do
	[ -f "$grubfile" ] || continue
	rel=${grubfile#"$source_root"/}
	# Comments document the ban; only live lines can violate it.
	body=$(grep -v '^[[:space:]]*#' "$grubfile" || true)
	# Token-scan every GRUB_CMDLINE_LINUX assignment...
	assigned=$(printf '%s\n' "$body" | sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/p')
	while IFS= read -r val; do
		[ -n "$val" ] || continue
		case " $val " in
		*' init='*)
			fail "$rel carries an init= override: $val"
			;;
		esac
	done <<EOF
$assigned
EOF
	# ...and any linux-line template or hook that names init outright.
	if printf '%s\n' "$body" | grep -E -q '(^|[[:space:]])init=/[^[:space:]]*'; then
		hit=$(printf '%s\n' "$body" | grep -E -o '(^|[[:space:]])init=/[^[:space:]]*' | head -1)
		fail "$rel names an init binary:$hit"
	fi
done
printf '%s\n' 'init-contract: no init= in packaged bootloader defaults'

# --- A2. no built-in command line in any packaged kernel config --------
#
# SEV1 2026-10-23 (corrected): built kernels define NO command line at
# all - the bootloader owns the entire kernel command line. Eleven
# vendored configs carried a built-in console= (first dual with ttyS0,
# then tty0-only); any built-in console policy from the kernel package
# is wrong, and CONFIG_CMDLINE_OVERRIDE=y would let a built-in overrule
# the bootloader outright. Deployments with a real serial console set
# it explicitly on their own kernel line.

for kconf in "$source_root"/*/files/config-*; do
	[ -f "$kconf" ] || continue
	rel=${kconf#"$source_root"/}
	if grep -q '^CONFIG_CMDLINE_BOOL=y$' "$kconf"; then
		fail "$rel sets CONFIG_CMDLINE_BOOL (built kernels define no cmdline)"
	fi
	cmdline=$(sed -n 's/^CONFIG_CMDLINE="\(.*\)"$/\1/p' "$kconf")
	if [ -n "$cmdline" ]; then
		fail "$rel CONFIG_CMDLINE is not empty: $cmdline"
	fi
	if grep -q '^CONFIG_CMDLINE_OVERRIDE=y$' "$kconf"; then
		fail "$rel sets CONFIG_CMDLINE_OVERRIDE (the bootloader cmdline must win)"
	fi
done
printf '%s\n' 'init-contract: no built-in cmdline in packaged kernel configs'

# --- B. init.c names exactly /sbin/init ----------------------------------
#
# Same extraction as the initramfs suite's runtime-adjacent check; this
# gate fails the tree even when that suite is not run.

cands=$(sed -n '/init_candidates\[\] = {/,/};/p' "$source_root/saphira-initramfs-tools/files/init.c") ||
	fail 'cannot extract init_candidates from init.c'
printf '%s\n' "$cands" | grep -Fq '"/sbin/init"' ||
	fail 'init.c init_candidates does not name /sbin/init'
paths=$(printf '%s\n' "$cands" | grep -o '"[^"]*"' | sort -u) ||
	fail 'cannot list init.c init_candidates paths'
[ "$paths" = '"/sbin/init"' ] ||
	fail "init.c init_candidates names more than /sbin/init: $paths"
printf '%s\n' 'init-contract: init.c names exactly /sbin/init'

# --- C. no /usr/sbin/init init-reference in payloads ----------------------
#
# lxc's init.lxc helper is a distinctly-named container binary invoked
# explicitly by lxc-start, never PID 1: match the exact path only.

bad_refs=$(grep -rn --exclude-dir=.git -E '/usr/sbin/init([^.]|$)' "$source_root" 2>/dev/null |
	while IFS= read -r hit; do
		path=${hit%%:*}
		case "$path" in
		*/files/*)
			# Payload files: only init.lxc coexistence is legitimate.
			# Comment lines document the ban; live lines violate it.
			case "$hit" in
			*init.lxc*) continue ;;
			esac
			text=${hit#*:}; text=${text#*:}
			stripped=$(printf '%s\n' "$text" | sed 's/^[[:space:]]*//')
			case "$stripped" in
			'#'*|'*'*)
				continue
				;;
			esac
			printf '%s\n' "$hit"
			;;
		*/recipe.sh)
			# Recipes: removal lines, absence assertions and comments
			# document and enforce the ban.
			text=${hit#*:}; text=${text#*:}
			case "$text" in
			*'rm -f'*|*'[ -e'*|*'[ -L'*|*'#'*) continue ;;
			esac
			printf '%s\n' "$hit"
			;;
		*/tests/*)
			# Tests assert the absence; they must name it to check it.
			continue
			;;
		*.md)
			# Policy documentation names the banned path deliberately.
			continue
			;;
		*)
			printf '%s\n' "$hit"
			;;
		esac
	done) || fail 'init-contract payload scan failed'
[ -z "$bad_refs" ] || fail "merged-usr init references in payloads:${bad_refs}"
printf '%s\n' 'init-contract: no /usr/sbin/init init-reference in payloads'

# --- D. no recipe symlinks sbin/init --------------------------------------
#
# PID 1 arrives via upstream install (openrc) or a real copy (systemd
# recipe_install, fail-closed there). A recipe-created symlink is either
# a cross-tree compat link or masks a missing canonical binary.

bad_links=$(grep -rn --exclude-dir=.git -E 'ln[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^[:space:]]*[[:space:]]+[^[:space:]]*sbin/init([^.]|$)' \
	"$source_root" --include=recipe.sh 2>/dev/null || true)
[ -z "$bad_links" ] || fail "recipe symlinks sbin/init:${bad_links}"
printf '%s\n' 'init-contract: no recipe symlinks sbin/init'

# --- E. the V6/V7 guard locks are present (not silently reverted) ---------
#
# The SEV1 regression reached a live machine through a test that required
# it. If either lock below disappears, this gate fails rather than going
# quiet.

grep -Fq "carries an init= override" "$source_root/saphira-packager/tests/recipe-rules.sh" ||
	fail 'recipe-rules.sh lost the init= refusal lock (V6 reverted?)'
grep -Fq "lost init= belt-and-braces" "$source_root/saphira-packager/tests/recipe-rules.sh" &&
	fail 'recipe-rules.sh still requires the init= line (V6 reverted?)'
grep -Fq "init= override" "$source_root/saphira-image-creator/tests/clean-image-guards.sh" ||
	fail 'clean-image-guards.sh lost the init= refusal lock (V7 reverted?)'
printf '%s\n' 'init-contract: V6/V7 guard locks present'

printf '%s\n' 'init-contract: OK (bootloader defaults, init.c, payload refs, sbin/init links, guard locks)'
