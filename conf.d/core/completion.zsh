# ===========================================================================
# conf.d/core/completion.zsh — tab-completion settings (zstyle)
#
# zstyle sets a style for completion contexts. ':completion:*' matches all of
# them. Menu selection and coloured lists are provided by the zsh/complist
# module.
# To turn it off: rename the file so it no longer ends in .zsh.
# ===========================================================================

# menu: how the candidate list is shown.
#   select           start menu selection at once: Tab then moves through the
#                    candidates with the arrow keys
#   select=N         start menu selection only when there are at least N matches
#   no-select        turn menu selection off
# A value containing "select" starts it unconditionally (zshcompsys, "menu").
zstyle ':completion:*' menu select

# matcher-list: how typed text is matched against candidates. Each string is
# one match spec, tried in turn. A spec prefixed with + is added to the list.
#   ''                   plain completion, no matching rules
#   'm:{a-z}={A-Z}'      typed lowercase also matches uppercase candidates
#   'm:{a-zA-Z}={A-Za-z}' both directions
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# list-colors: colours for candidates, same syntax as GNU ls.
#   "${(s.:.)LS_COLORS}"  split $LS_COLORS on ':' and use its entries
#   ''                    the GNU ls default colours
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
