#!/bin/sh
# Fixture SSH backend for saphira-kubernetes tests: emulates authorised
# remote hosts without any network. Records every invocation; answers
# canned facts and kubectl outputs per $FIXTURE_MODE (healthy|broken).
# Usage: SAPHIRA_KUBERNETES_SSH=this-file (plus FIXTURE_LOG + FIXTURE_MODE).
set -eu
target=$1
shift
printf 'ssh %s %s\n' "$target" "$*" >> "${FIXTURE_LOG:?}/ssh.log"
mode=${FIXTURE_MODE:-healthy}
case $mode in
healthy) ready=Ready; phase=Running ;;
*) ready=NotReady; phase=CrashLoopBackOff ;;
esac
case "$*" in
*kubelet\ --version*) printf 'Kubernetes v1.37.1\n' ;;
*kubeadm\ version*) printf 'v1.37.1\n' ;;
*kubectl\ version*) printf 'Client Version: v1.37.1\n' ;;
*containerd\ --version*) printf 'containerd 2.4.2\n' ;;
*uname\ -r*) printf '7.3.0-rc1\n' ;;
*kubelet_joined*) printf 'kubelet_joined=yes\n' ;;
*cni_plugins*) printf 'cni_plugins=present\n' ;;
*command\ -v\ helm*|*command\ -v\ crictl*|*command\ -v\ k9s*) [ "$mode" = "healthy" ] || exit 1; printf '/usr/bin/stub\n' ;;
*get\ deployment\ headlamp*) [ "$mode" = "healthy" ] || exit 1; printf 'headlamp 1/1 1 1 2d\n' ;;
*docker\ inspect*portainer-ce*) [ "$mode" = "healthy" ] || exit 1; printf 'running portainer/portainer-ce:2.45.2\n' ;;
*cluster-info*) [ "$mode" = "healthy" ] || exit 1; printf 'Kubernetes control plane is running\n' ;;
*get\ nodes*) printf 'demo %s\n' "$ready" ;;
*get\ pods*) printf 'demo 1/1 %s\n' "$phase" ;;
*kubeadm\ token\ create*) printf 'abcdef.0123456789abcdef\n' ;;
*openssl\ x509*) printf 'deadbeef  -\n' ;;
*kubeadm\ init*|*kubeadm\ join*|*apk\ add*|*drain*|*uncordon*|*delete\ node*|*kubeadm\ reset*|*mkdir*|*cp\ *) printf 'fixture-applied\n' ;;
*nslookup*) [ "$mode" = "healthy" ] || exit 1; printf 'Name: ok\nAddress: ::1\n' ;;
*delete\ pod*) printf 'pod deleted\n' ;;
*) printf 'fixture-output\n' ;;
esac
exit 0
