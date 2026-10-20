#!/bin/sh

# python-xstatic-angular-fileupload: Angular-FileUpload 12.2.13 (XStatic packaging standard)
#
# XStatic-Angular-FileUpload 12.2.13.2, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular-fileupload
pkgver=12.2.13.2
pkgrel=1
pkgarch=noarch
pkgdesc="Angular-FileUpload 12.2.13 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular-FileUpload
repo=saphira
url=https://pypi.org/project/XStatic-Angular-FileUpload/
source=https://files.pythonhosted.org/packages/a1/ea/8aba18a7d6db6bb83e665ea10696aa46723171cc7216014140adb7420236/xstatic_angular_fileupload-12.2.13.2.tar.gz
sha256=1c277b444df01b85974900147770eea9675959e112ee831affffe7fb114dc4b2

depends="
    python3
    python-xstatic
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
"

recipe_build()
{
    :
}

recipe_install()
{
    python3 -m pip install \
        --no-index \
        --no-deps \
        --ignore-installed \
        --no-build-isolation \
        --no-compile \
        --no-cache-dir \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
