#!/bin/sh
# Seed the Saphira Gopher content root for geomyidae.
#
# Called by BOTH init implementations (OpenRC start_pre and systemd
# ExecStartPre).  Idempotent and conservative:
#   - creates the dedicated unprivileged gopher account only if the
#     base layout has not already provided it (canonical definition
#     lives in saphira-baselayout accounts.tsv, UID/GID 123);
#   - creates /srv/gopher;
#   - seeds default content ONLY where the operator has no content yet;
#   - never overwrites or deletes existing operator content, so package
#     upgrades and service restarts are safe.

set -eu

SHARE=/usr/share/geomyidae/default
SRV=/srv/gopher

# Dedicated unprivileged service account (see saphira-baselayout
# accounts.tsv: gopher UID 123 / GID 123, home /srv/gopher).
if ! id gopher >/dev/null 2>&1; then
	if [ -x /usr/sbin/groupadd ] && ! getent group gopher >/dev/null 2>&1; then
		/usr/sbin/groupadd -g 123 gopher
	fi
	if [ -x /usr/sbin/useradd ]; then
		/usr/sbin/useradd -r -u 123 -g gopher -d "$SRV" \
			-s /sbin/nologin gopher
	fi
fi

install -d -m 0755 "$SRV"

# Holding page: seed only if there is no operator gophermap at all.
[ -e "$SRV/gophermap" ] || \
	install -m 0644 "$SHARE/gophermap" "$SRV/gophermap"
[ -e "$SRV/about.txt" ] || \
	install -m 0644 "$SHARE/about.txt" "$SRV/about.txt"

# Sub-menus referenced by the default gophermap.  Geomyidae generates
# directory listings when a directory has no gophermap/index.gph, so the
# placeholders below just give the menu something honest to show.
for d in docs packages downloads; do
	install -d -m 0755 "$SRV/$d"
done

[ -e "$SRV/docs/README.txt" ] || printf '%s\n' \
	'Saphira documentation placeholder.' \
	'Replace or extend the files under /srv/gopher/docs/.' \
	> "$SRV/docs/README.txt"

[ -e "$SRV/packages/README.txt" ] || printf '%s\n' \
	'Saphira package placeholder.' \
	'See https://saphira.vm2.uk/ for the APK repository.' \
	> "$SRV/packages/README.txt"

[ -e "$SRV/downloads/README.txt" ] || printf '%s\n' \
	'Saphira downloads placeholder.' \
	'Put downloadable files here and link them from /srv/gopher/gophermap.' \
	> "$SRV/downloads/README.txt"
