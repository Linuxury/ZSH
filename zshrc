# Live entry point: sources conf.d/*.zsh in name order.
# ZSH_HOME is the directory this file lives in (default checkout: ~/.zsh).
export ZSH_HOME=${${(%):-%x}:A:h}
for _f in $ZSH_HOME/conf.d/*.zsh(N); do source $_f; done
unset _f
