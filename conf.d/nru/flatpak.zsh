# ===========================================================================
# conf.d/nru/flatpak.zsh — the "Flatpak" step of nru
#
# Updates Flatpak apps in both scopes through the shared nixos-flatpak-update
# script, which the NixOS config installs (modules/system/graphical/graphical.nix)
# and which the weekly update timers run too. nru (nru.zsh) calls the step only
# where the flatpak command exists; remove that call to turn it off.
# ===========================================================================

# ---------------------------------------------------------------------------
# _nru_flatpak_bar — update Flatpak apps in user and system scope.
# Takes no arguments; always returns 0 (failures are shown, not fatal).
#
# Runs, behind a spinner (log: flatpak.log):
#   nixos-flatpak-update --user
#   /run/wrappers/bin/sudo -n /run/current-system/sw/bin/nixos-flatpak-update --system
#     -n   never prompt for a password; system scope works through a NixOS
#          sudo rule that allows exactly this command without one
#          (/run/wrappers/bin/sudo is the setuid sudo)
#
# The script prints one line per result: "<scope> <kind> [APP] [text]" with
# scope user|system and kind updated | failed | uptodate | skipped. A line
# starting "sudo:" is sudo's own error (for example no matching rule).
# How the lines are shown:
#   skipped no-flathub        no Flathub remote: the whole step is hidden
#                             (_nru_hide), as on the alex user's hosts, which have
#                             their Flatpak remotes removed
#   any failed / sudo error   "✗ <apps> failed", the first three messages, and
#                             the apps that did update
#   any updated               "N updated" and a tree of apps with their scope
#   nothing                   quiet "up to date"
# Skipped with a note when nixos-flatpak-update is not installed yet (it
# arrives with the next rebuild) and when the pull found no network.
# ---------------------------------------------------------------------------
_nru_flatpak_bar() {
  local icon=$_NRU_FP name="Flatpak" log="$_NRU_CACHE/flatpak.log" line scope kind app rest f
  local -a updated failed

  if ! command -v nixos-flatpak-update &>/dev/null; then
    _nru_quiet "$icon" "$name" "⏭ skipped (updater installs with this rebuild)" "updater installs with this rebuild"; return 0
  fi
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  _nru_spin "$icon" "$name" "updating" "$log" zsh -c \
    'nixos-flatpak-update --user; /run/wrappers/bin/sudo -n /run/current-system/sw/bin/nixos-flatpak-update --system'

  while IFS= read -r line; do
    if [[ $line == sudo:* ]]; then failed+=("system scope|$line"); continue; fi
    read -r scope kind app rest <<< "$line"
    case $kind in
      skipped) [[ $app == no-flathub ]] && { _nru_hide; return 0 } ;;
      updated) updated+=("$rest  ($scope)") ;;
      failed)  [[ $app == - ]] && app="$scope scope"   # listing failed, no app
               failed+=("${app##*.}|$rest") ;;
    esac
  done < "$log"

  if (( $#failed )); then
    _nru_row "$icon" "$name" "✗ ${(j:, :)${failed%%|*}} failed${updated:+ · others updated}"
    for f in ${failed[1,3]}; do printf "       %s%s\n" "$_NRU_IND" "${f#*|}"; done
    (( $#updated )) && _nru_tree "${updated[@]}"
  elif (( $#updated )); then
    _nru_ok "$icon" "$name" "$#updated updated"
    _nru_tree "${updated[@]}"
  else
    _nru_quiet "$icon" "$name" "up to date"
  fi
  return 0
}

