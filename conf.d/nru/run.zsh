# ---------------------------------------------------------------------------
# _nixos_run — core rebuild helper used by nr / nru / nrt
#
# - Shows a build header with hostname (unless called from nru)
# - Holds a systemd sleep/idle inhibit lock for the full build duration
# - Tees all output to a temp log, pipes it through _nix_fetch_filter
# - On success: package diff via nvd; on failure: short summary + saved log
# - Calls nixos-log-rebuild to write warnings and an entry to the vault
#
# Leaves for callers: _NIXOS_LAST_GEN, _NIXOS_SWITCH_TIME, _NIXOS_CHANGED,
# and _NRU_FAIL_KIND (on failure).
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

  # One background ticker draws all live progress (see _nru_ticker);
  # &| starts it disowned so zsh never prints job notifications.
  print eval > "$statef"
  _nru_ticker "$statef" &|
  _NRU_TICKER_PID=$!

  # systemd-inhibit keeps the machine awake mid-build; the lock releases when
  # the command exits. The log (tee) captures raw output before the filter.
  # { } always { } is zsh's "finally" — the ticker is stopped even on errors.
  {
    systemd-inhibit --what=sleep:idle --who=nixos-rebuild \
      --why="NixOS rebuild in progress" \
      "$@" 2>&1 | tee "$tmplog" | _nix_fetch_filter "$statef" "$_NRU_CACHE"
    exit_code=$pipestatus[1]
  } always {
    kill "$_NRU_TICKER_PID" 2>/dev/null
    printf "\r\033[K" > /dev/tty
  }

  # Exit 4 = switch done but some units failed to start — still a success.
  (( exit_code == 0 || exit_code == 4 )) && ok=1
  new_system=$(readlink -f /run/current-system 2>/dev/null)
  _NIXOS_CHANGED=0
  [[ -n "$old_system" && "$old_system" != "$new_system" ]] && _NIXOS_CHANGED=1

  # Package diff — only when the system actually changed.
  if (( ok && _NIXOS_CHANGED )) && command -v nvd &>/dev/null; then
    local fmt_output
    fmt_output=$(nvd diff "$old_system" "$new_system" | _fmt_nvd)
    if [[ -n "$fmt_output" ]]; then
      printf '%s\n' "$fmt_output"
      printf '%s\n' "$fmt_output" > "$_NRU_CACHE/last-packages.txt"
    fi
  fi

  # Warnings + update log to the vault (never fails the shell). The
  # generation number goes to _NIXOS_LAST_GEN; the rest of the output is the
  # "─── Flagged ───" block, printed so it's visible at rebuild time.
  _NIXOS_LAST_GEN=""
  if command -v nixos-log-rebuild &>/dev/null; then
    local outcome="success" log_out
    (( ok )) || outcome="failure"
    log_out=$(nixos-log-rebuild --outcome "$outcome" --log "$tmplog" 2>&1) || true
    _NIXOS_LAST_GEN=$(printf '%s' "$log_out" | grep -oE 'gen [0-9]+' | grep -oE '[0-9]+' | head -1)
    [[ -n "$log_out" ]] && printf '%s\n' "$log_out" | grep -v '^nixos-log-rebuild:'
  fi

  # Switch duration from systemd's "Consumed … over 1.924s wall clock time"
  # line (hidden by _nix_fetch_filter).
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

# Rebuild and switch to the current flake config.
nr() {
  _nixos_run sudo nixos-rebuild switch -L --no-link --flake "$NIXOS_CONFIG#$(hostname)"
}

# Test rebuild — activates now without touching the boot entry (safe for risky changes).
nrt() {
  _nixos_run sudo nixos-rebuild test -L --no-link --flake "$NIXOS_CONFIG#$(hostname)"
}

