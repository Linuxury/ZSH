# ===========================================================================
# conf.d/shortcuts/hytale.zsh — start Hytale with the sc-controller gamepad profile
#
# Usage: hytale [args...]      (args are passed to the Flatpak launcher)
# Before launch, sets the Steam Controller profile in sc-controller to
# "XBox Controller", so the controller sends gamepad events. The Desktop
# profile sends mouse and keyboard events instead. After the launcher
# returns, the previous profile is set back.
# Needs scc (sc-controller) with scc-daemon running, and the Flatpak app
# com.hypixel.HytaleLauncher.
# To turn it off: rename the file so it no longer ends in .zsh.
# ===========================================================================
hytale() {
  local SCC="scc"
  local PREV_PROFILE
  # scc info prints "Profile: <name>" for the running driver; keep everything
  # after "Profile:" so names with spaces stay whole. scc errors are hidden;
  # an empty result falls back to "Desktop".
  PREV_PROFILE=$($SCC info 2>/dev/null | sed -n 's/^.*[Pp]rofile:[[:space:]]*//p' | head -n 1)
  [[ -z "$PREV_PROFILE" ]] && PREV_PROFILE="Desktop"

  # scc set-profile [controller_id] "profile name". Quote names with spaces.
  # Other profile names: scc list-profiles.
  $SCC set-profile "XBox Controller" 2>/dev/null
  # Same restore as below, run if the shell gets EXIT, INT or TERM first. The
  # single quotes delay $SCC and $PREV_PROFILE expansion until the trap runs.
  trap '$SCC set-profile "$PREV_PROFILE" 2>/dev/null' EXIT INT TERM

  # flatpak run APP [ARGUMENT…]: starts the launcher and waits for it to exit.
  flatpak run com.hypixel.HytaleLauncher "$@"

  # Normal path: restore the profile, then remove the trap.
  $SCC set-profile "$PREV_PROFILE" 2>/dev/null
  trap - EXIT INT TERM
}
