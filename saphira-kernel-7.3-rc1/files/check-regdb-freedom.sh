#!/bin/sh
# check-regdb-freedom.sh - cfg80211 signature-freedom policy gate.
#
# Sourced by the saphira-kernel-$kver recipe_build() after
# `make olddefconfig` and by builder tests. Pure config-file logic
# over explicit path arguments (no builder globals), so the policy is
# unit-testable without compiling a kernel -- same conventions as
# check-no-initramfs-builtins.sh.
#
# Policy: signature verification of the wireless regulatory database
# must NOT be mandatory. Enforcement must have NO resolution path to
# =y in the final .config:
#
# - REQUIRE_SIGNED_REGDB is a standalone bool (visible whenever
#   CERTIFICATION_ONUS=y): it must be literally present as
#   "# CONFIG_... is not set". A missing line is a different state
#   and fails -- olddefconfig would then apply the Kconfig default.
# - USE_KERNEL_REGDB_KEYS additionally depends on REQUIRE_SIGNED: with
#   REQUIRE explicitly off, Kconfig drops the line entirely instead of
#   serializing "is not set" (a bool can never serialize as =n). That
#   absence is PROVABLY safe -- and only then -- because (a) the
#   unmet dependency forces n on any re-resolution, and (b) the
#   Kconfig default is patched to n below. Either =y anywhere fails.
#
# This gate runs AFTER the final olddefconfig (post-patch, post-merge),
# because the original defect was precisely the build process
# re-enabling defaults behind the recipe's back. A signed database may
# still ship (wireless-regdb); it must simply never be required.
#
# Usage: check_regdb_freedom <config-path> [<kconfig-path>]
#   config-path:  final .config to assert on (required).
#   kconfig-path: net/wireless/Kconfig to assert the default-n patch on
#                 (optional; when given, both gatekeeper defaults must
#                 read "default n", so an absent line can never
#                 re-resolve to enforced).

rgd_die()
{
	printf 'regdb-freedom: %s\n' "$*" >&2
	return 1
}

check_regdb_freedom()
{
	config=$1
	kconfig=${2-}
	[ -f "$config" ] || { rgd_die "config not found: $config"; return 1; }
	# No path to =y, ever: reject the enabled spelling outright.
	if grep -qxF 'CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=y' "$config" || \
	   grep -qxF 'CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS=y' "$config"; then
		rgd_die "regdb enforcement enabled in $config"
		return 1
	fi
	# REQUIRE_SIGNED has no dependency gate: absence would let a
	# default decide, so the explicit "is not set" line is mandatory.
	grep -qxF '# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set' "$config" || \
		{ rgd_die "REQUIRE_SIGNED_REGDB not explicitly disabled in $config"; return 1; }
	# USE_KERNEL_REGDB_KEYS may be absent: with REQUIRE_SIGNED
	# explicitly off its `depends on` is unmet and olddefconfig drops
	# the line instead of serializing "is not set" (a bool can never
	# serialize as =n). Absence is safe ONLY in that state: the unmet
	# dependency forces n on any re-resolution, and the Kconfig
	# default below is patched to n as the second lock. So: =y fails
	# (rejected above); absent passes only with REQUIRE off; an
	# explicit "is not set" line always passes.
	if ! grep -qxF '# CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS is not set' "$config"; then
		grep -qxF '# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set' "$config" || \
			{ rgd_die "USE_KERNEL_REGDB_KEYS absent without REQUIRE off in $config"; return 1; }
	fi
	if [ -n "$kconfig" ]; then
		[ -f "$kconfig" ] || { rgd_die "Kconfig not found: $kconfig"; return 1; }
		for sym in CFG80211_REQUIRE_SIGNED_REGDB CFG80211_USE_KERNEL_REGDB_KEYS; do
			grep -A3 "^config $sym\$" "$kconfig" | grep -qxF '	default n' || \
				{ rgd_die "$sym default not patched to n in $kconfig"; return 1; }
		done
	fi
}
