#!/bin/sh

# saphira-nginx-waf: Saphira's nginx WAF wiring (config only).
#
# Depends on the full stack - engine (modsecurity), connector
# (nginx-mod-modsecurity), rules (owasp-crs) - plus nginx itself,
# and assembles them into one Include chain under
# /etc/nginx/modsec. Inert until the admin opts in (see
# files/waf-snippet.conf.example): installing this package changes
# no request path on its own.
#
# modsecurity.conf derives from the engine's recommended template
# (shipped in the modsecurity payload) with three Saphira choices:
# blocking ON, audit log under /var/log/nginx, absolute unicode
# map path. crs-setup.conf is the upstream 4.x example verbatim
# (anomaly scoring, paranoia 1); tune it in place.

pkgname=saphira-nginx-waf
pkgver=1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira nginx WAF wiring: ModSecurity + CRS include chain"
license=MIT
origin=saphira-nginx-waf
repo=saphira
url=https://saphira.vm2.uk/

# Local/meta payload: no upstream source (see recipe rules).
depends="
    modsecurity
    nginx
    nginx-mod-modsecurity
    owasp-crs
"
makedepends=""

recipe_build()
{
	# Engine template and CRS setup come from the dependency
	# payloads in the build root (full depends closure is
	# installed, as with qmail's lib_deps read).
	engine_conf=/usr/share/doc/modsecurity/modsecurity.conf-recommended
	crs_setup=/usr/share/owasp-crs/crs-setup.conf.example
	unicode_map=/usr/share/doc/modsecurity/unicode.mapping
	test -f "$engine_conf" || { echo "ERROR: $engine_conf missing (modsecurity payload?)" >&2; return 1; }
	test -f "$crs_setup" || { echo "ERROR: $crs_setup missing (owasp-crs payload?)" >&2; return 1; }
	test -f "$unicode_map" || { echo "ERROR: $unicode_map missing (modsecurity payload?)" >&2; return 1; }
	mkdir -p "$SRC/modsec"
	{
		printf '%s\n' '# Saphira nginx WAF engine config: derived from the'
		printf '%s\n' '# modsecurity recommended template with blocking ON,'
		printf '%s\n' '# audit log under /var/log/nginx, absolute unicode map.'
		printf '%s\n' '# Log-only first: set SecRuleEngine DetectionOnly.'
		sed -e 's|^SecRuleEngine DetectionOnly|SecRuleEngine On|' \
			-e 's|^SecAuditLog /var/log/modsec_audit.log|SecAuditLog /var/log/nginx/modsec_audit.log|' \
			-e 's|^SecUnicodeMapFile unicode.mapping 20127|SecUnicodeMapFile /etc/nginx/modsec/unicode.mapping 20127|' \
			"$engine_conf"
	} > "$SRC/modsec/modsecurity.conf"
	grep -q '^SecRuleEngine On$' "$SRC/modsec/modsecurity.conf" ||
		{ echo "ERROR: SecRuleEngine rewrite missed" >&2; return 1; }
	grep -q '^SecAuditLog /var/log/nginx/modsec_audit.log$' "$SRC/modsec/modsecurity.conf" ||
		{ echo "ERROR: SecAuditLog rewrite missed" >&2; return 1; }
	cp -a "$crs_setup" "$SRC/modsec/crs-setup.conf"
	cp -a "$unicode_map" "$SRC/modsec/unicode.mapping"
	cp -a "$RECIPE_DIR/files/modsec-main.conf" "$SRC/modsec/main.conf"
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/etc/nginx/modsec"
	install -m 0644 "$SRC/modsec/modsecurity.conf" \
		"$SRC/modsec/crs-setup.conf" \
		"$SRC/modsec/unicode.mapping" \
		"$SRC/modsec/main.conf" \
		"$PKGDEST/etc/nginx/modsec/"
	install -m 0644 "$RECIPE_DIR/files/waf-snippet.conf.example" \
		"$PKGDEST/etc/nginx/modsec/waf-snippet.conf.example"
}
