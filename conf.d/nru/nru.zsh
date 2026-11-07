# ---------------------------------------------------------------------------
# nru — update everything, then rebuild.
# Pulls nixos-config, updates all flake inputs, Proton-CachyOS (gaming hosts)
# and Flatpaks (graphical hosts), rebuilds, then summarises. Failures at each
# step offer only the options that make sense for that failure.
# ---------------------------------------------------------------------------
nru() {
  _NRU_START=$EPOCHSECONDS
  mkdir -p "$_NRU_CACHE"

  # TRAPINT fires on Ctrl+C even in interactive zsh (unlike `always` blocks).
  # Stops the ticker and offers a retry. Self-removes so later Ctrl+C in the
  # shell behaves normally.
  TRAPINT() {
    unfunction TRAPINT 2>/dev/null
    kill "$_NRU_TICKER_PID" 2>/dev/null
    printf "\r\033[K\n" >/dev/tty
    if [[ $(_nru_menu "✗" "Rebuild Interrupted" "R:retry" "q:quit") == r ]]; then
      _NRU_NO_HEADER=1 _nru_rebuild
    fi
    return 130
  }

  echo ""
  echo "══════════════════════════════════════════════════════════"
  printf "  ↻  Update & Rebuild  ·  %s\n" "$(hostname)"
  echo "══════════════════════════════════════════════════════════"
  echo ""

  _NRU_GRP_PREV=
  _nru_group Flake "up to date"
  _nru_git_bar || { _nru_group_end; unfunction TRAPINT 2>/dev/null; return 1 }
  # New shells load the copy built into the last rebuild. If a checkout of this
  # repo exists, re-source it silently so the remaining steps run its latest nru
  # code (functions resolve at call time; only this function's step list stays
  # old). Without a checkout the new code arrives with the next rebuild.
  [[ -r ${ZSH_HOME:-$HOME/.zsh}/zshrc ]] && _NRU_QUIET=1 source "${ZSH_HOME:-$HOME/.zsh}/zshrc"
  _nru_inputs_bar
  _nru_group_end

  _nru_group Pinned "all current"
  command -v steam   &>/dev/null && _nru_update_proton_ge
  command -v steam   &>/dev/null && _nru_update_proton_cachyos
  command -v steam   &>/dev/null && _nru_update_proton_wineland
  command -v photocraft &>/dev/null && { _nru_update_craft_apps; _nru_craft_unpackaged }
  { _nru_is_lock_writer || command -v claude-desktop &>/dev/null } && _nru_update_claude_desktop
  _nru_is_lock_writer && { _nru_update_plex; _nru_update_zennotes; _nru_update_vscodium_ext }
  _nru_group_end

  command -v flatpak &>/dev/null && { _nru_group Flatpak "up to date"; _nru_flatpak_bar; _nru_group_end }

  echo ""
  _NRU_NO_HEADER=1 _nru_rebuild
  local rc=$?
  unfunction TRAPINT 2>/dev/null
  return $rc
}

