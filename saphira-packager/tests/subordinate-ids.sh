#!/bin/sh
#
# subordinate-ids.sh: guard unprivileged subordinate-ID mapping.
#
# An unprivileged user may only map UIDs/GIDs the administrator allocated to
# them in /etc/subuid and /etc/subgid. The pieces that make that work are all
# individually removable, and each removal is silent:
#
#   shadow --enable-subordinate-ids  without it, useradd allocates nothing and
#                                    upstream's own setcap of the helpers is
#                                    skipped (src/Makefile.am gates it on
#                                    ENABLE_SUBIDS)
#   /etc/subuid + /etc/subgid        managed files, shipped present-but-empty
#   login.defs SUB_UID_*/SUB_GID_*   the allocation policy itself
#   newuidmap/newgidmap privilege    setuid, because the payload cannot carry
#                                    file capabilities
#   makepkg capability refusal       stops a recipe shipping an unprivileged
#                                    helper and calling it done
#
# The last two are load-bearing together. Saphira's apk payload has no xattr
# channel, so a setcap'd helper ships with NO privilege: shadow r6 was
# published that way, newuidmap arrived mode 0755, and it could never map a
# UID for anyone. makepkg now refuses such a payload outright.
#
# usage: subordinate-ids.sh [RECIPE-ROOT]

set -eu

root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
shadow=$root/shadow/recipe.sh
makepkg=$root/saphira-packager/files/makepkg

checks=0
fail()
{
	printf '%s\n' "subordinate-ids: $*" >&2
	exit 1
}
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

# --- 1. the recipe must actually enable the feature -------------------

[ -f "$shadow" ] || fail "shadow recipe is missing: $shadow"
[ -f "$makepkg" ] || fail "makepkg is missing: $makepkg"

printf '%s\n' "subordinate-ids: shadow"

# The flags are checked on the configure INVOCATION only. Matching the whole
# file is wrong: these strings appear in the recipe's own comments, which
# discuss the flags precisely in order to record why they are set the way
# they are, and a whole-file grep cannot tell a decision from a note about
# a decision. That is not hypothetical -- the first version of this test
# failed on its own comment.
configure_line=$(sed -n '/\.\/configure/,/^[^ \t]/p' "$shadow" | head -20)

[ -n "$configure_line" ] ||
	fail "could not find the ./configure invocation in $shadow"

grep -q -- '--enable-subordinate-ids' <<EOF || fail "shadow does not pass --enable-subordinate-ids; useradd allocates no ranges and the helpers are never privileged"
$configure_line
EOF
ok "shadow: --enable-subordinate-ids"

# The removal must not have come back in the other direction either.
if grep -q -- '--without-subordinate-ids' <<EOF
$configure_line
EOF
then
	fail "shadow still passes --without-subordinate-ids"
fi
ok "shadow: --without-subordinate-ids is gone"

# Capabilities cannot survive the payload, so the recipe must not rely on
# them. --with-fcaps is what produced the broken r6.
if grep -q -- '--with-fcaps' <<EOF
$configure_line
EOF
then
	fail "shadow uses --with-fcaps; the apk payload drops security.capability, so the helpers would ship unprivileged"
fi
ok "shadow: --with-fcaps is not used (setuid is the mechanism that survives)"

# The databases must be created by the recipe, not assumed to pre-exist.
grep -q 'etc/subuid' "$shadow" || fail "shadow does not ship /etc/subuid"
grep -q 'etc/subgid' "$shadow" || fail "shadow does not ship /etc/subgid"
grep -qE 'install -D -m 0644 /dev/null "\$PKGDEST/etc/sub(uid|gid)"' "$shadow" ||
	fail "the subordinate-ID databases are not installed 0644 from /dev/null (present but empty, never hard-coded)"
ok "shadow: /etc/subuid and /etc/subgid shipped 0644 and empty"

# The policy must be asserted to arrive, since a dropped login.defs block
# makes useradd silently unable to allocate anything.
for knob in SUB_UID_MIN SUB_UID_MAX SUB_UID_COUNT \
	SUB_GID_MIN SUB_GID_MAX SUB_GID_COUNT; do
	grep -q "$knob" "$shadow" ||
		fail "the install does not assert $knob reached login.defs"
done
ok "shadow: the SUB_UID_*/SUB_GID_* policy is asserted at install time"

# The helpers' privilege must be verified, and specifically as setuid: a
# looser "privileged somehow" check is satisfied by a capability that the
# payload then drops.
grep -qE 'newuidmap' "$shadow" || fail "newuidmap is not checked at install"
grep -qE 'not setuid' "$shadow" ||
	fail "the install does not require the helpers to be setuid specifically"
ok "shadow: the helpers are required to be setuid, not merely privileged"

# --- 2. makepkg must refuse capabilities ------------------------------

printf '%s\n' "subordinate-ids: makepkg capability refusal"
grep -q 'security.capability' "$makepkg" ||
	fail "makepkg does not mention security.capability; a capability-bearing payload would ship with no privilege and no error"
grep -q 'os.listxattr' "$makepkg" ||
	fail "makepkg does not inspect xattrs, so the capability check cannot be running"
ok "makepkg: refuses a payload carrying security.capability"

# The setuid restoration must still be there: it is what makes the
# supported mechanism work, and the capability refusal is only safe because
# of it.
grep -q '0o7000' "$makepkg" ||
	fail "makepkg no longer records special mode bits; setuid would be lost to the chown"
ok "makepkg: setuid/setgid mode bits are still recorded and restored"

printf '%s\n' "subordinate-ids: OK ($checks checks)"
