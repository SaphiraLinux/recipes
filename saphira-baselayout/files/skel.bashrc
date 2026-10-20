# Saphira default /root and user shell configuration.
#
# Thin by design: system-wide interactive defaults live in /etc/bashrc
# (prompt, history, completion, aliases). This file only wires them in
# and leaves room for per-user overrides below. Existing home copies
# of older, thicker skeletons keep working standalone and are never
# rewritten. Nothing here writes outside the user's own home.

# System defaults first; personal overrides after.
[ -r /etc/bashrc ] && . /etc/bashrc

# Non-interactive shells inherit the environment without running startup
# files at all, so nothing here can slow down scp, rsync or a cron job.
case $- in
	*i*) ;;
	*) return ;;
esac

# Personal additions below this line. Examples (uncomment to use):
# alias ..='cd ..'
# export EDITOR=nano