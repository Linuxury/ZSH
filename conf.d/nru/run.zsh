# ===========================================================================
# conf.d/nru/run.zsh — the rebuild runner and the nr / nrt commands
#
# _nixos_run is the one place that executes a nixos-rebuild command with
# progress, logging and a failure summary. nr and nrt are one-line wrappers
# around it; nru (via _nru_rebuild in rebuild.zsh) calls it too.
# The commands are available in every interactive shell that loads this file;
# remove the file (and the callers) to turn them off.
# ===========================================================================

# ---------------------------------------------------------------------------
# _nixos_run — run a rebuild command with live progress, logging and a summary.
#
# Usage: _nixos_run CMD [ARGS...]      CMD is the full rebuild command line
# Example: _nixos_run sudo nixos-rebuild switch -L --no-link --flake "$NIXOS_CONFIG#$(hostname)"
# Returns CMD's exit code. Environment: _NRU_NO_HEADER=1 skips the banner
# (nru prints its own).
#
# What it does:
#   - shows a "Rebuild · hostname" banner (unless _NRU_NO_HEADER is set)
#   - holds a systemd sleep/idle inhibit lock for the whole build
#   - tees all output to a temp log and pipes it through _nix_fetch_filter,
#     which condenses it and feeds the live ticker (_nru_ticker)
#   - on a change: package diff via nvd, saved to last-packages.txt
#   - runs nixos-log-rebuild to record warnings and an update entry
#   - on failure: short summary (_nru_fail_summary) and the full log saved to
#     last-failure.log
#
# Variables left for callers:
#   _NIXOS_LAST_GEN     generation number (empty if unknown)
#   _NIXOS_SWITCH_TIME  how long the switch took, e.g. "1.9s" (empty if unknown)
#   _NIXOS_CHANGED      1 if /run/current-system now points somewhere new, else 0
#   _NRU_FAIL_KIND      failure category, set on failure by _nru_fail_summary
#   _NRU_TICKER_PID     pid of the ticker (nru's Ctrl+C handler kills it)
# ---------------------------------------------------------------------------
_nixos_run() {
  local tmplog exit_code old_system new_system statef ok=0
  mkdir -p "$_NRU_CACHE"
  tmplog=$(mktemp /tmp/nixos-rebuild-XXXXXX.log)
  statef="$_NRU_CACHE/.ticker.$$"
  old_system=$(readlink -f /run/current-system 2>/dev/null)

  if [[ -z "$_NRU_NO_HEADER" ]]; then
    echo ""
    echo "══════════════════════════════════════════════════════════"
    printf "  ↻  Rebuild  ·  %s\n" "$(hostname)"
    echo "══════════════════════════════════════════════════════════"
    echo ""
  fi

  # One background ticker draws all live progress (see _nru_ticker). `&|`
  # starts it in the background and disowns it so zsh never prints job
  # notices. The state file starts as "eval" (shows "Evaluating…") until
  # _nix_fetch_filter overwrites it with fetch/build progress.
  print eval > "$statef"
  _nru_ticker "$statef" &|
  _NRU_TICKER_PID=$!

  # systemd-inhibit takes an inhibitor lock for as long as the command runs
  # and releases it when the command exits.
  #   --what=sleep:idle   block suspend and idle actions; "shutdown" is left out
  #                       so the machine can still be powered off. The default
  #                       is idle:sleep:shutdown; other values: handle-power-key,
  #                       handle-suspend-key, handle-hibernate-key,
  #                       handle-lid-switch, handle-reboot-key.
  #   --who=STRING        who holds the lock (shown by `systemd-inhibit --list`)
  #   --why=STRING        the reason shown there
  #   --mode=             block (default) | block-weak | delay; not set here
  # tee "$tmplog" saves the raw output before the filter condenses it.
  # { try } always { cleanup } is zsh's "finally": the always block runs
  # whether or not the try block hit an error, so the ticker is stopped
  # and its line erased either way.
  {
    systemd-inhibit --what=sleep:idle --who=nixos-rebuild \
      --why="NixOS rebuild in progress" \
      "$@" 2>&1 | tee "$tmplog" | _nix_fetch_filter "$statef" "$_NRU_CACHE"
    # $pipestatus[1] is the exit status of the first command in the pipeline
    # (systemd-inhibit, which passes on the rebuild's status), not of tee or
    # the filter.
    exit_code=$pipestatus[1]
  } always {
    kill "$_NRU_TICKER_PID" 2>/dev/null
    printf "\r\033[K" > /dev/tty
  }

  # switch-to-configuration (run by nixos-rebuild) exits 4 when the switch
  # itself completed but some units failed to reload or start. The new system
  # is active, so it counts as success.
  (( exit_code == 0 || exit_code == 4 )) && ok=1
  new_system=$(readlink -f /run/current-system 2>/dev/null)
  _NIXOS_CHANGED=0
  [[ -n "$old_system" && "$old_system" != "$new_system" ]] && _NIXOS_CHANGED=1

  # Package diff — only when the system actually changed. `nvd diff OLD NEW`
  # compares two store paths (add -s / --selected for direct dependencies
  # only, --sort ORDER to change the sort); _fmt_nvd lays the result out as a
  # table. The same table is kept in last-packages.txt.
  if (( ok && _NIXOS_CHANGED )) && command -v nvd &>/dev/null; then
    local fmt_output
    fmt_output=$(nvd diff "$old_system" "$new_system" | _fmt_nvd)
    if [[ -n "$fmt_output" ]]; then
      printf '%s\n' "$fmt_output"
      printf '%s\n' "$fmt_output" > "$_NRU_CACHE/last-packages.txt"
    fi
  fi

  # nixos-log-rebuild writes the rebuild's warnings and an update entry to the
  # vault; `|| true` keeps a logging problem from failing the shell.
  #   --outcome success|failure   how the rebuild ended
  #   --log FILE                  the raw log to scan for warnings
  #   (also accepted: --host NAME, --vault PATH)
  # Its output carries the generation number ("gen N", stored in
  # _NIXOS_LAST_GEN) and the "─── Flagged ───" block of warnings, which is
  # printed so it is visible at rebuild time; its own "nixos-log-rebuild:"
  # status line is dropped.
  _NIXOS_LAST_GEN=""
  if command -v nixos-log-rebuild &>/dev/null; then
    local outcome="success" log_out
    (( ok )) || outcome="failure"
    log_out=$(nixos-log-rebuild --outcome "$outcome" --log "$tmplog" 2>&1) || true
    _NIXOS_LAST_GEN=$(printf '%s' "$log_out" | grep -oE 'gen [0-9]+' | grep -oE '[0-9]+' | head -1)
    [[ -n "$log_out" ]] && printf '%s\n' "$log_out" | grep -v '^nixos-log-rebuild:'
  fi

  # Switch duration, read from the "… over 1.924s wall clock time" part of
  # systemd's "Consumed …" line (hidden by _nix_fetch_filter). The duration
  # is "<n>min <n>s", "<n>ms" or "<n>s" and is shown as "1m 4s" or "1.9s".
  _NIXOS_SWITCH_TIME=""
  local _wall
  _wall=$(grep -oE 'over [0-9.]+(min|ms|s)( [0-9.]+s)? wall clock' "$tmplog" | tail -1)
  _wall=${${_wall#over }% wall clock}
  case $_wall in
    *min*) _NIXOS_SWITCH_TIME=$(printf '%dm %.0fs' ${_wall%%min*} ${${_wall##* }%s}) ;;
    *ms)   _NIXOS_SWITCH_TIME=$(printf '%.1fs' $(( ${_wall%ms} / 1000.0 ))) ;;
    *s)    _NIXOS_SWITCH_TIME=$(printf '%.1fs' ${_wall%s}) ;;
  esac

  if (( ! ok )); then
    cp "$tmplog" "$_NRU_CACHE/last-failure.log"
    _nru_fail_summary "$_NRU_CACHE/last-failure.log"
  fi

  rm -f "$tmplog" "$statef"
  return $exit_code
}

# ---------------------------------------------------------------------------
# nr — rebuild and switch to the current flake config. Usage: nr
#   switch   build, activate now, and make it the boot default
#   -L       print full build logs (--print-build-logs)
#   --no-link   do not create a ./result symlink
#   --flake PATH#HOST   build nixosConfigurations.HOST of the flake at PATH;
#                       HOST here is this machine's hostname
# Alternatives for the action word: boot (next boot only), test (see nrt),
# build (build only), dry-build, dry-activate.
# ---------------------------------------------------------------------------
nr() {
  _nixos_run sudo nixos-rebuild switch -L --no-link --flake "$NIXOS_CONFIG#$(hostname)"
}

# ---------------------------------------------------------------------------
# nrt — test rebuild. Usage: nrt
# Same flags as nr, but `test` activates the new config now without adding it
# to the boot menu, so a reboot returns to the last switched generation — a
# safe way to try risky changes.
# ---------------------------------------------------------------------------
nrt() {
  _nixos_run sudo nixos-rebuild test -L --no-link --flake "$NIXOS_CONFIG#$(hostname)"
}

