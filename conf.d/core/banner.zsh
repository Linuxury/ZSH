# System info on startup — random image from ~/Pictures/Fastfetch/
# (skipped when nru re-sources this file after pulling a new version)
# Over SSH (also after su), plain logo: kitty-direct sends a file *path*, which
# the local terminal can't open, so the text lands on top of the screen.
(( _NRU_QUIET )) || () {
  local imgs=( ~/Pictures/Fastfetch/*.{png,jpg,jpeg,webp}(N) )
  if [[ -z $SSH_CONNECTION ]] && (( ${#imgs} )); then
    fastfetch --logo-type kitty-direct --logo "${imgs[$RANDOM % $#imgs + 1]}"
  else
    fastfetch --logo-type auto
  fi
}

