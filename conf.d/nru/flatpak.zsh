# ---------------------------------------------------------------------------
# _nru_flatpak_bar — updates Flatpak apps in user AND system scope through the
# shared nixos-flatpak-update script (modules/system/graphical/default.nix;
# the weekly timers use the same one). System scope runs via a passwordless
# sudo rule for exactly that command. Silent where Flathub is absent (Alex's
# machines, where the remote is deliberately removed for child safety).
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

