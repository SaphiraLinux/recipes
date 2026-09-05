#!/bin/sh

# RETIRED generation-zero marker. akadata-base-abi-0.1 was an artifact of
# the historical Stage3/Stage4 bootstrap universe; saphira-base-abi 0.2
# replaces it in the Genesis transition. This recipe exists only so the
# builder records a deliberate, documented skip instead of the package
# looking forgotten. The builder must never build or resolve it:
#   - saphira-build scan skips disabled recipes (reported, not queued)
#   - buildpkg refuses to build a disabled recipe
#   - resolvepkg refuses to satisfy dependencies from a disabled recipe
# Dependencies must migrate to saphira-base-abi.

pkgname=akadata-base-abi
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='RETIRED akadata base ABI marker (superseded by saphira-base-abi-0.2)'
license='MIT'
origin=akadata-base-abi
repo=saphira
url=https://saphira.vm2.uk/

disabled=yes
disabled_reason='superseded by saphira-base-abi-0.2; Genesis ABI transition'

recipe_build()
{
	echo "ERROR: akadata-base-abi is disabled: $disabled_reason" >&2
	return 1
}

recipe_install()
{
	echo "ERROR: akadata-base-abi is disabled: $disabled_reason" >&2
	return 1
}
