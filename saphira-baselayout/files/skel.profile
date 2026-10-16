# Saphira login shell profile.
#
# Read by every login shell. Interactive and non-login shells skip the
# rest of it; the PATH and umask below are the only things a session
# should not start without.

if [ -n "${BASH_VERSION-}" ]; then
	[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi

# Standard directories only: /usr/bin and /usr/sbin first, then the
# non-usrmerged /bin and /sbin. Saphira does not use a usr-merged
# filesystem, so both pairs are real and both belong on PATH.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

umask 022

# Console and locale defaults, only when the shell is interactive and no
# locale has been chosen explicitly.
if [ -z "${LANG-}" ] && command -v locale >/dev/null 2>&1; then
	if locale -a 2>/dev/null | grep -qix 'C.utf8\|en_US.utf8'; then
		LANG=C.UTF-8
		export LANG
	fi
fi

for term in xterm-256color xterm screen linux vt100; do
	if [ -z "${TERM-}" ] && [ -t 1 ]; then
		case $TERM in
		'') TERM=$term ;;
		esac
		break
	fi
done

unset -f term 2>/dev/null || true

cd "$HOME" 2>/dev/null || true