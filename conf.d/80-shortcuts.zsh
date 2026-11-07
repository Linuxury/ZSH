# ---------------------------------------------------------------------------
# Shortcuts — short names for long commands. Listed in the README.
# ---------------------------------------------------------------------------

# NixOS (nr, nrt and nru are functions in the nru-* files)
alias nrr='sudo nixos-rebuild switch --rollback'
alias ngc='sudo nix-collect-garbage --delete-older-than 30d'
alias ngens='sudo nix-env --list-generations --profile /nix/var/nix/profiles/system'

# Git
alias add='git add .'
alias clone='git clone'
alias cloned='git clone --depth=1'
alias commit='git commit -m'
alias pull='git pull'
alias push='git push'
alias pushm='git push -u origin main'
alias pusho='git push origin'

# gpush "message" — add everything, commit with the message, push
gpush() {
  (( $# )) || { print -u2 "usage: gpush <commit message>"; return 1 }
  git add . && git commit -m "$*" && git push
}

