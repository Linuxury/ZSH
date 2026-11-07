# ---------------------------------------------------------------------------
# hytale — launch Hytale with gamepad sc-controller profile, restore after
#
# sc-controller's Desktop profile consumes all Steam Controller input as
# mouse/keyboard. Switching to "XBox Controller" before launch makes it
# emit real gamepad events that Hytale (Chromium gamepad API) can detect.
# The Desktop profile is restored when the game exits, whether cleanly or
# via Ctrl-C / kill.
# ---------------------------------------------------------------------------
hytale() {
  local SCC="scc"
  local PREV_PROFILE
  PREV_PROFILE=$($SCC info 2>/dev/null | grep -i 'profile:' | awk '{print $2}')
  [[ -z "$PREV_PROFILE" ]] && PREV_PROFILE="Desktop"

  $SCC set-profile "XBox Controller" 2>/dev/null
  trap '$SCC set-profile "$PREV_PROFILE" 2>/dev/null' EXIT INT TERM

  flatpak run com.hypixel.HytaleLauncher "$@"

  $SCC set-profile "$PREV_PROFILE" 2>/dev/null
  trap - EXIT INT TERM
}

