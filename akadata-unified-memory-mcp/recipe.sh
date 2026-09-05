#!/bin/sh

# RETIRED package name. akadata-unified-memory-mcp is superseded by
# saphira-unified-memory-mcp (r18 there; payload and /etc/akadata-memory
# config path deliberately unchanged so deployed runtime configs keep
# working). This recipe exists only so the builder records a deliberate,
# documented skip. Consumers must depend on saphira-unified-memory-mcp.

pkgname=akadata-unified-memory-mcp
pkgver=3.13.5
pkgrel=17
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='RETIRED akadata MCP memory suite (superseded by saphira-unified-memory-mcp)'
license='MIT'
origin=akadata-unified-memory-mcp
repo=saphira
url=https://saphira.vm2.uk/

disabled=yes
disabled_reason='renamed to saphira-unified-memory-mcp; Genesis rebrand'

recipe_build()
{
	echo "ERROR: akadata-unified-memory-mcp is disabled: $disabled_reason" >&2
	return 1
}

recipe_install()
{
	echo "ERROR: akadata-unified-memory-mcp is disabled: $disabled_reason" >&2
	return 1
}
