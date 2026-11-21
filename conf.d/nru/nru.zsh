# ===========================================================================
# conf.d/nru/nru.zsh — nru: pull, update everything, rebuild
#
# Defines `nru`, the one-command update for this host. Which steps run depends
# on what is installed or which host it is (tested with `command -v` and
# _nru_is_lock_writer):
#   Flake group    git pull (git.zsh), then flake inputs (inputs.zsh)
#   Pinned group   Proton builds when steam exists (proton.zsh); photocraft
#                  apps (craft.zsh); claude-desktop on the lock-writer host or
#                  where installed; plex, zennotes, mailcraft and VSCodium
#                  extensions on the lock-writer host only (updaters.zsh)
#   Flatpak group  when flatpak exists (flatpak.zsh)
#   then the rebuild (_nru_rebuild in rebuild.zsh, which runs _nixos_run from
#   run.zsh) and a summary.
# Each step that fails offers only the options that make sense for that
# failure. To drop a step, remove its line from the function below.
# ===========================================================================

# ---------------------------------------------------------------------------
# nru — update everything, then rebuild.
# Usage: nru            (no arguments)
# Returns the rebuild's exit code, 1 if the git step aborted, 130 after Ctrl+C.
# Sets _NRU_START (seconds since epoch) for the summary's total time.
# ---------------------------------------------------------------------------
nru() {
  _NRU_START=$EPOCHSECONDS
  mkdir -p "$_NRU_CACHE"

  # TRAPINT is zsh's handler for SIGINT (Ctrl+C); zsh runs it when the shell
  # receives the signal. Here it stops the rebuild ticker, clears the line and
  # offers retry (rebuild only, no header) or quit. It returns 130 (128 plus
  # SIGINT's signal number 2) and removes itself, so Ctrl+C behaves normally
  # again once nru is over.
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

  # Step 1 — Flake group. _NRU_GRP_PREV= forgets what an earlier run printed
  # so the first group starts without a leading blank line. A failed or
  # declined pull ends nru here.
  _NRU_GRP_PREV=
  _nru_group Flake "up to date"
  _nru_git_bar || { _nru_group_end; unfunction TRAPINT 2>/dev/null; return 1 }
  # New shells load the copy of this repo built into the last rebuild. If a
  # checkout exists at $ZSH_HOME (default ~/.zsh), re-source its zshrc silently
  # (_NRU_QUIET=1 suppresses the startup banner) so the remaining steps run the
  # pulled nru code: functions are looked up when called, only this function's
  # own step list stays as loaded. Without a checkout the new code arrives with
  # the next rebuild.
  [[ -r ${ZSH_HOME:-$HOME/.zsh}/zshrc ]] && _NRU_QUIET=1 source "${ZSH_HOME:-$HOME/.zsh}/zshrc"
  _nru_inputs_bar
  _nru_group_end

  # Step 2 — Pinned group: software whose version is pinned in the config and
  # bumped here. Each updater runs only where its program or role exists.
  _nru_group Pinned "all current"
  command -v steam   &>/dev/null && _nru_update_proton_ge
  command -v steam   &>/dev/null && _nru_update_proton_cachyos
  command -v steam   &>/dev/null && _nru_update_proton_wineland
  command -v photocraft &>/dev/null && { _nru_update_craft_apps; _nru_craft_unpackaged }
  { _nru_is_lock_writer || command -v claude-desktop &>/dev/null } && _nru_update_claude_desktop
  _nru_is_lock_writer && { _nru_update_plex; _nru_update_zennotes; _nru_update_mailcraft; _nru_update_vscodium_ext }
  _nru_group_end

  # Step 3 — Flatpak group, only where flatpak is installed.
  command -v flatpak &>/dev/null && { _nru_group Flatpak "up to date"; _nru_flatpak_bar; _nru_group_end }

  # Step 4 — rebuild and summarise. _NRU_NO_HEADER=1 stops _nixos_run printing
  # its own "Rebuild · host" banner, since nru printed one at the top.
  echo ""
  _NRU_NO_HEADER=1 _nru_rebuild
  local rc=$?
  unfunction TRAPINT 2>/dev/null
  return $rc
}

