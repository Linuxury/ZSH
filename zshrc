# ===========================================================================
# zshrc — entry point for a plain zsh install
#
# Add this line to ~/.zshrc (README.md, "Install"):
#   source ~/.zsh/zshrc
# It sets ZSH_HOME to the checkout, then sources every conf.d/<folder>/*.zsh.
# NixOS builds do not read this file. init.nix joins the same files instead.
#
# Folders load in alphabetical order: core, herdr, nru, shortcuts, user.
# Inside a folder, files load by name (00-env.zsh before banner.zsh).
# Keep "user" last so ~/.env.local can override the files before it.
# Only *.zsh files exactly one folder down are loaded. Hidden files (leading
# dot) and files nested deeper are skipped.
# ===========================================================================

# ZSH_HOME: the directory this file lives in. nru uses it to find zshrc again.
# The export overwrites any ZSH_HOME set before it.
#   ${(%):-%x}  path of the file being read (%x), with prompt escapes expanded
#               (the (%) flag)
#   :A          absolute path, with symbolic links resolved
#   :h          head: the directory part, without the file name
# The install path in README.md is ~/.zsh.
export ZSH_HOME=${${(%):-%x}:A:h}

# Source each conf.d/<folder>/*.zsh file. The glob sorts by name, which gives
# the folder order above. (N): a pattern with no match is skipped, not an error.
for _f in $ZSH_HOME/conf.d/*/*.zsh(N); do source $_f; done
unset _f
