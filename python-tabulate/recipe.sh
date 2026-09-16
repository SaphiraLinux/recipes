#!/bin/sh

# Pretty-print tabular data in Python: Pretty-print tabular data in Python
#
# PyPI tabulate 0.10.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Version comes from git via setuptools-scm; the tarball carries no .git, so the version is pre-seeded (same value as the release).

pkgname=python-tabulate
pkgver=0.10.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Pretty-print tabular data in Python"
license="MIT"
origin=tabulate
repo=saphira
url=https://pypi.org/project/tabulate/
source=https://files.pythonhosted.org/packages/46/58/8c37dea7bbf769b20d58e7ace7e5edfe65b849442b00ffcdd56be88697c6/tabulate-0.10.0.tar.gz
sha256=e2cfde8f79420f6deeffdeda9aaec3b6bc5abce947655d17ac662b126e48a60d

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-setuptools-scm
"

recipe_build()
{
    :
}

recipe_install()
{
    export SETUPTOOLS_SCM_PRETEND_VERSION=0.10.0
    python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
