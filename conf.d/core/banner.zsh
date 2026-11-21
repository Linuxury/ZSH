# ===========================================================================
# conf.d/core/banner.zsh — fastfetch system info, printed when a shell starts
#
# Shows a random image from ~/Pictures/Fastfetch/ (png, jpg, jpeg, webp).
# Over SSH, or when that folder has no images, a logo is shown without one.
# Skipped when nru re-sources zshrc after an update (nru sets _NRU_QUIET=1).
# To turn it off: delete this file, or rename it so it no longer ends in .zsh
# (zshrc and init.nix load only *.zsh files).
# ===========================================================================

# Show the banner unless _NRU_QUIET is set. The () { … } form is a zsh
# anonymous function: its `local` variables stay inside it.
(( _NRU_QUIET )) || () {
  # Image files in the folder. (N): a glob with no match becomes an empty
  # array instead of an error. {png,jpg,jpeg,webp} is brace expansion.
  local imgs=( ~/Pictures/Fastfetch/*.{png,jpg,jpeg,webp}(N) )
  # SSH_CONNECTION is set in SSH sessions and kept by su (without -).
  # The image branch is skipped in that case.
  if [[ -z $SSH_CONNECTION ]] && (( ${#imgs} )); then
    # --logo-type kitty-direct: tells the terminal emulator to read the image
    # data from this file path (kitty graphics protocol). The path is on this
    # machine, so it does not work over SSH.
    # Other --logo-type values (fastfetch --help logo-type):
    #   kitty       image rendered with the Kitty graphics protocol
    #   kitty-icat  image shown through `kitten icat` (needs the kitten binary)
    #   sixel, iterm, chafa (ASCII art), raw
    # $RANDOM is 0–32767; % $#imgs gives 0..n-1, +1 because zsh arrays start at 1.
    fastfetch --logo-type kitty-direct --logo "${imgs[$RANDOM % $#imgs + 1]}"
  else
    # --logo-type auto: with no --logo value, fastfetch detects a logo itself.
    # Other choices: builtin (built-in ASCII art), small, none (no logo).
    fastfetch --logo-type auto
  fi
}
