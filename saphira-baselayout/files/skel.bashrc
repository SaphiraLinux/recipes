# Saphira default /root and user shell configuration.
#
# Deliberately short: a server console, not a desktop. Everything here
# is safe for an unprivileged session; nothing writes outside the user's
# own home.

# Non-interactive shells inherit the environment without running startup
# files at all, so nothing here can slow down scp, rsync or a cron job.
case $- in
	*i*) ;;
	*) return ;;
esac

HISTFILE=$HOME/.bash_history
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize
shopt -s noemptycmd

# A prompt that shows user, host and directory, with colour only when
# the terminal can do it.
if [ -t 1 ]; then
	PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
else
	PS1='\u@\h:\w\$ '
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Colour when the terminal supports it, and pager defaults that behave in
# a pipe. GNU coreutils is the shipped userland, so these are safe.
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'

export PAGER=less
export LESS='-R'
export EDITOR=vi

umask 022