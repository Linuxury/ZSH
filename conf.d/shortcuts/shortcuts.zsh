# ===========================================================================
# conf.d/shortcuts/shortcuts.zsh — short names for long commands
#
# Aliases and one function. The full list is in README.md ("Shortcuts").
# To turn it off: delete the lines you do not want, or rename the file so it
# no longer ends in .zsh.
# ===========================================================================

# NixOS. nr, nrt and nru are functions in conf.d/nru/ (run.zsh, nru.zsh).
#   nrr    sudo nixos-rebuild switch --rollback
#            switch back to the previous system generation.
#            "boot --rollback" changes only the default for the next boot.
#   ngc    sudo nix-collect-garbage --delete-older-than 30d
#            delete generations older than 30 days, then collect garbage.
#            -d / --delete-old removes all old generations, with no age limit.
#   ngens  sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
#            list the system generations.
alias ht='herdr-team launch full'   # lead + 4 idle workers (perf, bugs, ui, simplify)
alias nrr='sudo nixos-rebuild switch --rollback'
alias ngc='sudo nix-collect-garbage --delete-older-than 30d'
alias ngens='sudo nix-env --list-generations --profile /nix/var/nix/profiles/system'

# Git. add stages everything, so check git status first. For part of a file
# or a change, use git add <path> or git add -p (pick hunks interactively).
#   add     git add .                 stage everything in the current directory
#   clone   git clone                 clone a repository
#   cloned  git clone --depth=1       shallow clone: only the latest commit
#   commit  git commit -m             the message is the next argument
#   pull    git pull
#   push    git push
#   pushm   git push -u origin main   push and set origin/main as upstream (-u)
#   pusho   git push origin           push to a named branch: pusho <branch>
alias add='git add .'
alias clone='git clone'
alias cloned='git clone --depth=1'
alias commit='git commit -m'
alias pull='git pull'
alias push='git push'
alias pushm='git push -u origin main'
alias pusho='git push origin'

# gpush <message> — git add ., git commit -m "<message>", git push.
# Stops at the first step that fails (&&). With no argument it prints usage
# and returns 1. Example: gpush "fix typo in README"
gpush() {
  (( $# )) || { print -u2 "usage: gpush <commit message>"; return 1 }
  git add . && git commit -m "$*" && git push
}
