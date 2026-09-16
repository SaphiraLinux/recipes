#!/bin/sh

SAPHIRA_CONFIG_FILE=${SAPHIRA_CONFIG_FILE:-/etc/saphira/package_builder.sh}
SAPHIRA_RECIPE_ROOT=${SAPHIRA_RECIPE_ROOT:-/recipes}
SAPHIRA_REFERENCE_RECIPE_ROOT=${SAPHIRA_REFERENCE_RECIPE_ROOT:-/reference-package-recipes}
SAPHIRA_CPORTS_ROOT=${SAPHIRA_CPORTS_ROOT:-/cports}
SAPHIRA_BUILD_ROOT=${SAPHIRA_BUILD_ROOT:-/build}
# Scratch for every controller tool, test harness, and namespace backing
# store. Host /tmp is never used for Saphira work: it is wiped on reboot,
# shared, and invisible. /build/tmp is writable by the builder user,
# visible, and disposed with the work that used it.
SAPHIRA_TMPDIR=${SAPHIRA_TMPDIR:-/build/tmp}
SAPHIRA_PACKAGE_TMP=${SAPHIRA_PACKAGE_TMP:-/var/tmp/saphira-package}
# Persistent content-addressed source cache (verified upstream archives,
# keyed by sha256). Survives workdir disposal so rebuilds never re-fetch;
# bind-mounted into the isolated build namespace at the same path.
SAPHIRA_SOURCE_CACHE=${SAPHIRA_SOURCE_CACHE:-/var/cache/saphira/sources}
SAPHIRA_REPO_DIR=${SAPHIRA_REPO_DIR:-/out/stage4/packages}
# Generation repositories, oldest first: every publication lands in ALL
# listed repositories (each is an append-only archive holding real APK
# copies, never links). The LAST entry is the live repository that
# consumers (resolvepkg, checkpkg, installpkg, clean-root seeding)
# resolve against. Both generations ship by default: hatchling is the
# permanent archive, hatched the current view. A further generation
# boundary (hatched > ...) is a deliberate operator act: seed the new
# repository, then edit this list.
SAPHIRA_REPO_NAMES=${SAPHIRA_REPO_NAMES:-hatchling hatched}
# Retired migration-era package names excluded from a repository genesis
# seed (space-separated). They stay as historical r0 artifacts in the
# archives; obsolete names are never bumped just to make a count zero.
SAPHIRA_GENESIS_EXCLUDE=${SAPHIRA_GENESIS_EXCLUDE:-}
# Generic parallel-version-line policy (empty/unset: tool defaults apply).
SAPHIRA_VERSION_LINES_FILE=${SAPHIRA_VERSION_LINES_FILE:-}
SAPHIRA_INCOMING_DIR=${SAPHIRA_INCOMING_DIR:-/out/stage4/incoming}
# Hatched retention: the live generation keeps the newest
# SAPHIRA_RETAIN_GENERATIONS NVRs per package name (default 2). Older
# NVRs retire inside the signer's publication transaction unless a live
# dependent needs exactly them or they sit on SAPHIRA_RETAIN_NVR
# (space-separated NVRs or nvr.apk filenames, e.g. "acl-2.3.2-r1").
# Archive generations are never pruned.
SAPHIRA_RETAIN_GENERATIONS=${SAPHIRA_RETAIN_GENERATIONS:-2}
SAPHIRA_RETAIN_NVR=${SAPHIRA_RETAIN_NVR:-}
SAPHIRA_SIGN_KEY=${SAPHIRA_SIGN_KEY:-/root/apk-signing/akadata-repository.rsa}
SAPHIRA_TRUST_KEY=${SAPHIRA_TRUST_KEY:-/etc/apk/keys/akadata-repository.rsa.pub}
# Canonical host-side module signing key. The builder exposes it read-only
# inside the isolated build namespace at the fixed path
# /keys/module-signing.pem (recipes must use that path; they never learn
# the host path). The file must be readable by the builder user - plain
# 0600 root:root is NOT enough; grant UID access, e.g.:
#   setfacl -m u:smalley:r /etc/saphira/keys/module-signing.pem
# (group membership does not survive the user namespace, UID ACLs do).
# saphira-module.pem is byte-identical but retired: zero consumers, kept
# only until every reference is proven migrated, then removed.
SAPHIRA_MODULE_KEY=${SAPHIRA_MODULE_KEY:-/etc/saphira/keys/module-signing.pem}
SAPHIRA_RELEASE_STATE=${SAPHIRA_RELEASE_STATE:-/var/lib/saphira-build/releases}
SAPHIRA_RELEASE_POLICY=${SAPHIRA_RELEASE_POLICY:-monotonic}
SAPHIRA_ARCH=${SAPHIRA_ARCH:-x86_64}
SAPHIRA_BINDIR=${SAPHIRA_BINDIR:-/usr/bin}
SAPHIRA_APK=${SAPHIRA_APK:-/usr/bin/apk}
SAPHIRA_BWRAP=${SAPHIRA_BWRAP:-/usr/bin/bwrap}
SAPHIRA_PYTHON=${SAPHIRA_PYTHON:-/usr/bin/python3}
SAPHIRA_METADATA_SHELL=${SAPHIRA_METADATA_SHELL:-/bin/bash}
SAPHIRA_METADATA_TIMEOUT=${SAPHIRA_METADATA_TIMEOUT:-10}
# Pinned distribution build epoch (2025-07-25T00:00:00Z): unchanged recipes
# rebuild to byte-identical APKs so republication stays idempotent under the
# immutable-filename rule.
SAPHIRA_SOURCE_DATE_EPOCH=${SAPHIRA_SOURCE_DATE_EPOCH:-1753401600}
# Package names are the boundary: the clean root is seeded exclusively
# from signed repository APKs. musl/musl-dev provide the C library,
# headers and static objects; saphira-kernel-headers the kernel UAPI;
# libxcrypt and flex the runtimes the old host-file manifest used to
# carry (libcrypt.so.2, libfl.so.2). Nothing is copied from the host.
SAPHIRA_BUILD_SEED=${SAPHIRA_BUILD_SEED:-saphira-baselayout saphira-base-abi apk-tools bash libcap coreutils curl diffutils findutils pcre2 mawk grep gzip patch sed tar acl attr xz bzip2 lz4 zstd ca-certificates python3 ccache which musl musl-dev saphira-kernel-headers libxcrypt flex}
SAPHIRA_HOST_RESOLV_CONF=${SAPHIRA_HOST_RESOLV_CONF:-/etc/resolv.conf}
SAPHIRA_HOST_HOSTS_FILE=${SAPHIRA_HOST_HOSTS_FILE:-/etc/hosts}
SAPHIRA_ROOT_RECIPE_MOUNT=${SAPHIRA_ROOT_RECIPE_MOUNT:-/recipes}
SAPHIRA_ROOT_REPO_MOUNT=${SAPHIRA_ROOT_REPO_MOUNT:-/repository}
SAPHIRA_ROOT_ARTIFACT_MOUNT=${SAPHIRA_ROOT_ARTIFACT_MOUNT:-/artifacts}
SAPHIRA_ROOT_BUILD_ROOT=${SAPHIRA_ROOT_BUILD_ROOT:-/var/tmp/saphira-build}
SAPHIRA_ROOT_PACKAGE_TMP=${SAPHIRA_ROOT_PACKAGE_TMP:-/tmp/package}
SAPHIRA_ROOT_BINDIR=${SAPHIRA_ROOT_BINDIR:-/usr/bin}
SAPHIRA_ROOT_SHELL=${SAPHIRA_ROOT_SHELL:-/bin/bash}
SAPHIRA_ROOT_PATH=${SAPHIRA_ROOT_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
SAPHIRA_ROOT_TMP=${SAPHIRA_ROOT_TMP:-/tmp}
SAPHIRA_ROOT_DEV=${SAPHIRA_ROOT_DEV:-/dev}
SAPHIRA_ROOT_PROC=${SAPHIRA_ROOT_PROC:-/proc}
SAPHIRA_ROOT_INPUT_MOUNT=${SAPHIRA_ROOT_INPUT_MOUNT:-/input}
SAPHIRA_ROOT_CONFIG_DIR=${SAPHIRA_ROOT_CONFIG_DIR:-/etc/saphira}
SAPHIRA_ROOT_APK_KEY_DIR=${SAPHIRA_ROOT_APK_KEY_DIR:-/etc/apk/keys}
SAPHIRA_HOST_APK_KEY_DIR=${SAPHIRA_HOST_APK_KEY_DIR:-/etc/apk/keys}
SAPHIRA_ROOT_SHELL_LINK=${SAPHIRA_ROOT_SHELL_LINK:-/bin/sh}

export SAPHIRA_CONFIG_FILE SAPHIRA_RECIPE_ROOT SAPHIRA_REFERENCE_RECIPE_ROOT SAPHIRA_CPORTS_ROOT
export SAPHIRA_BUILD_ROOT SAPHIRA_TMPDIR SAPHIRA_PACKAGE_TMP SAPHIRA_SOURCE_CACHE SAPHIRA_REPO_DIR SAPHIRA_INCOMING_DIR
export SAPHIRA_RETAIN_GENERATIONS SAPHIRA_RETAIN_NVR
export SAPHIRA_REPO_NAMES SAPHIRA_GENESIS_EXCLUDE SAPHIRA_VERSION_LINES_FILE
export SAPHIRA_SIGN_KEY SAPHIRA_TRUST_KEY SAPHIRA_MODULE_KEY SAPHIRA_ARCH SAPHIRA_BINDIR
export SAPHIRA_RELEASE_STATE SAPHIRA_RELEASE_POLICY
export SAPHIRA_APK SAPHIRA_BWRAP SAPHIRA_PYTHON SAPHIRA_METADATA_SHELL SAPHIRA_METADATA_TIMEOUT
export SAPHIRA_SOURCE_DATE_EPOCH
export SAPHIRA_BUILD_SEED
export SAPHIRA_HOST_RESOLV_CONF SAPHIRA_HOST_HOSTS_FILE
export SAPHIRA_ROOT_RECIPE_MOUNT SAPHIRA_ROOT_REPO_MOUNT
export SAPHIRA_ROOT_ARTIFACT_MOUNT SAPHIRA_ROOT_BUILD_ROOT SAPHIRA_ROOT_PACKAGE_TMP
export SAPHIRA_ROOT_BINDIR SAPHIRA_ROOT_SHELL SAPHIRA_ROOT_PATH SAPHIRA_ROOT_TMP SAPHIRA_ROOT_DEV SAPHIRA_ROOT_PROC
export SAPHIRA_ROOT_INPUT_MOUNT SAPHIRA_ROOT_CONFIG_DIR SAPHIRA_ROOT_APK_KEY_DIR
export SAPHIRA_HOST_APK_KEY_DIR SAPHIRA_ROOT_SHELL_LINK
