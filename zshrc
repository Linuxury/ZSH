# Live entry point: sources conf.d/<folder>/*.zsh. Folders load alphabetically:
# core, nru, shortcuts, user. Keep "user" last (it holds the ~/.env.local
# overrides). Inside a folder, files load by name.
# ZSH_HOME is the directory this file lives in (default checkout: ~/.zsh).
export ZSH_HOME=${${(%):-%x}:A:h}
for _f in $ZSH_HOME/conf.d/*/*.zsh(N); do source $_f; done
unset _f
