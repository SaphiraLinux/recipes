#!/bin/sh
# OpenRC/systemd parity for the kubelet service definitions.
#
# The systemd kubeadm drop-in supplies --bootstrap-kubeconfig,
# --kubeconfig and --config; the OpenRC init.d must assemble the
# equivalent arguments (OpenRC has no drop-in mechanism). These cases
# execute the real start_pre against fixture roots (absolute paths
# rewritten to the fixture) with stubbed OpenRC helpers, across the
# states a node actually passes through:
#
#   - empty: no kubeadm state (stray start; must not refuse, must not
#     invent flags — kubelet reports its own clear error);
#   - bootstrap-only: joining node (bootstrap present, kubelet.conf
#     absent — the case the old join gate refused, breaking join);
#   - joined: init/join complete (kubelet.conf + config.yaml);
#   - full: joined plus kubeadm flags and admin extras.
#
# Rootless: no OpenRC, no root, no kubelet run.

set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
initd=$here/../files/kubelet.initd

test -f "$initd" || { printf 'init.d missing: %s\n' "$initd" >&2; exit 1; }

# Scratch for fixture roots: the recipe tree may be mounted read-only
# (builder worker), so nothing is ever written beside this script.
scratch=${SAPHIRA_TMPDIR:-/build/tmp}/kubelet-parity-$$
mkdir -p "$scratch"
trap 'rm -rf "$scratch"' EXIT

failures=0

ok()
{
	printf 'ok       %s\n' "$*"
}

bad()
{
	printf 'FAIL     %s\n' "$*" >&2
	failures=$((failures + 1))
}

# Fixture layouts: space-separated relative paths to create.
# The tokens FLAGS and DEFAULT also write meaningful content.
EMPTY=""
BOOTSTRAP="etc/kubernetes/bootstrap-kubelet.conf"
JOINED="etc/kubernetes/kubelet.conf var/lib/kubelet/config.yaml"
FULL="etc/kubernetes/kubelet.conf var/lib/kubelet/config.yaml FLAGS DEFAULT"

run_case()
{
	name=$1
	layout=$2
	root=$scratch/parity-$name
	rm -rf "$root"
	mkdir -p "$root/var/lib/kubelet" "$root/etc/kubernetes" \
		"$root/etc/default" "$root/run/kubelet"
	for f in $layout; do
		case $f in
		FLAGS)
			printf 'KUBELET_KUBEADM_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock"\n' \
				> "$root/var/lib/kubelet/kubeadm-flags.env"
			;;
		DEFAULT)
			printf 'KUBELET_EXTRA_ARGS="--v=2"\n' > "$root/etc/default/kubelet"
			;;
		*)
			mkdir -p "$root/$(dirname "$f")"
			: > "$root/$f"
			;;
		esac
	done
	work=$root/work.sh
	sed -e "s|/etc/kubernetes|$root/etc/kubernetes|g" \
		-e "s|/var/lib/kubelet|$root/var/lib/kubelet|g" \
		-e "s|/etc/default/kubelet|$root/etc/default/kubelet|g" \
		-e "s|/run/kubelet|$root/run/kubelet|g" \
		"$initd" > "$work"
	(
		checkpath() { :; }
		eerror() { printf 'eerror: %s\n' "$*" >&2; }
		command_args="SENTINEL"
		# shellcheck disable=SC1090
		. "$work"
		start_pre
		printf '%s' "$command_args"
	)
}

expect()
{
	name=$1
	layout=$2
	root=$scratch/parity-$name
	want=""
	got=$(run_case "$name" "$layout")
	# Build the expectation from the same layout description.
	for f in $layout; do
		case $f in
		etc/kubernetes/bootstrap-kubelet.conf)
			want="$want --bootstrap-kubeconfig=$root/etc/kubernetes/bootstrap-kubelet.conf" ;;
		etc/kubernetes/kubelet.conf)
			want="$want --kubeconfig=$root/etc/kubernetes/kubelet.conf" ;;
		var/lib/kubelet/config.yaml)
			want="$want --config=$root/var/lib/kubelet/config.yaml" ;;
		FLAGS)
			want="$want --container-runtime-endpoint=unix:///run/containerd/containerd.sock" ;;
		DEFAULT)
			want="$want --v=2" ;;
		esac
	done
	if [ "$got" = "$want" ]; then
		ok "$name"
	else
		bad "$name: want [$want] got [$got]"
	fi
	rm -rf "$root"
}

expect empty "$EMPTY"
expect bootstrap-only "$BOOTSTRAP"
expect joined "$JOINED"
expect full "$FULL"

if [ "$failures" -ne 0 ]; then
	printf '%d FAILURES\n' "$failures" >&2
	exit 1
fi
printf 'all OpenRC parity cases pass\n'
