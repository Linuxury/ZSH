# ---------------------------------------------------------------------------
# _nru_rebuild — runs the rebuild; on failure offers only the options that
# can fix that kind of failure (Enter = the first, most likely fix). After a
# success: verdict, push (lock writer only), run summary, disk + reboot checks.
# Kept separate from nru so retries skip the git pull / input updates.
# ---------------------------------------------------------------------------
_nru_rebuild() {
  local cfg=$NIXOS_CONFIG code choice moved key
  local -a keys opts
  _NRU_ON_PREV=""

  while true; do
    _nixos_run sudo nixos-rebuild switch -L --no-link --flake "$cfg#$(hostname)"
    code=$?
    (( code == 0 || code == 4 )) && break
    (( code == 130 )) && _NRU_FAIL_KIND=interrupted

    # [p]revious lock only makes sense if this run changed the inputs.
    moved=""
    git -C "$cfg" diff --quiet HEAD -- flake.lock modules/gaming/default.nix pkgs/craft-apps/package.nix pkgs/claude-desktop/package.nix hosts/Media-Server/plex.json modules/services/zennotes/zennotes.json modules/development/editors/vscodium/extensions.json 2>/dev/null || moved=p
    case $_NRU_FAIL_KIND in
      hash)        keys=(f $moved l q) ;;
      hash-stale)  keys=(f l q) ;;
      hash-manual) keys=($moved l q) ;;
      build)       keys=($moved r l q) ;;
      config)      keys=($moved r l q) ;;
      download)    keys=(r q) ;;
      disk)        keys=(g q) ;;
      interrupted) keys=(r q) ;;
      *)           keys=(r $moved l q) ;;
    esac
    opts=()
    for key in $keys; do
      case $key in
        f) [[ $_NRU_FAIL_KIND == hash-stale ]] && opts+=("f:fix (remove override)") || opts+=("f:fix hash") ;;
        p) opts+=("p:previous lock") ;;
        r) opts+=("r:retry") ;;
        l) opts+=("l:log") ;;
        g) opts+=("g:GC + retry") ;;
        q) opts+=("q:quit") ;;
      esac
    done
    opts[1]="${(U)opts[1][1]}:${(C)opts[1][3]}${opts[1][4,-1]}"   # first option = default

    while true; do
      choice=$(_nru_menu "✗" "Rebuild Failed" "${opts[@]}")
      [[ $choice == l ]] || break
      less -R "$_NRU_CACHE/last-failure.log" </dev/tty >/dev/tty
    done

    case $choice in
      f) _nru_hash_fix ;;
      p) git -C "$cfg" restore flake.lock modules/gaming/default.nix pkgs/craft-apps/package.nix pkgs/claude-desktop/package.nix hosts/Media-Server/plex.json modules/services/zennotes/zennotes.json modules/development/editors/vscodium/extensions.json 2>/dev/null
         _NRU_ON_PREV=1
         printf "  ↺  restored flake.lock (nixpkgs %s) · rebuilding…\n\n" \
           "$(date -d @"$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified' "$cfg/flake.lock")" +%F)" ;;
      g) sudo nix-collect-garbage --delete-older-than 30d ;;
      r) ;;
      q) return 1 ;;
    esac
  done

  # ── Verdict ────────────────────────────────────────────────────────────────
  local -A st
  local kv
  for kv in ${(f)"$(<"$_NRU_CACHE/last-run.stats")"}; do st[${kv%%=*}]=${kv#*=}; done 2>/dev/null
  local -a info
  [[ -n $_NIXOS_LAST_GEN ]]    && info+=("generation $_NIXOS_LAST_GEN")
  [[ -n $_NIXOS_SWITCH_TIME ]] && info+=("switched in $_NIXOS_SWITCH_TIME")
  local extra="${info:+  (${(j: · :)info})}${_NRU_ON_PREV:+  · on previous lock}"
  echo ""
  if (( ! _NIXOS_CHANGED )); then
    printf "  ✓  No changes · still on generation %s\n" "${_NIXOS_LAST_GEN:-?}"
  elif (( code == 4 )); then
    printf "  ⚠  Rebuild done with %s unit failure%s%s\n" "${st[failed_units]:-?}" \
      "${${st[failed_units]:#1}:+s}" "$extra"
  else
    printf "  ✓  Rebuild successful%s\n" "$extra"
  fi

  # The scheduled auto-update skips its 3am run if nru ran within 20h, and the
  # session-start auto-update must not fire again right after nru.
  date +%s > /etc/nixos-last-update-time 2>/dev/null || true
  touch /run/user/$UID/nixos-update-done 2>/dev/null || true

  # ── Push shared state (lock writer only) ───────────────────────────────────
  # Git output is hidden on success, shown in full on failure.
  if _nru_is_lock_writer; then
    local git_out f
    local -a changed names
    changed=(${(f)"$(git -C "$cfg" status --porcelain -- flake.lock modules/gaming/default.nix pkgs/hash-fixes/default.nix pkgs/craft-apps/package.nix pkgs/claude-desktop/package.nix hosts/Media-Server/plex.json modules/services/zennotes/zennotes.json modules/development/editors/vscodium/extensions.json | cut -c4-)"})
    if (( $#changed )); then
      for f in $changed; do
        case $f in modules/gaming/default.nix) names+=("gaming module") ;; pkgs/craft-apps/package.nix) names+=("craft apps") ;; pkgs/claude-desktop/package.nix) names+=("claude desktop") ;; hosts/Media-Server/plex.json) names+=("plex") ;; modules/services/zennotes/zennotes.json) names+=("zennotes") ;; modules/development/editors/vscodium/extensions.json) names+=("vscodium ext") ;; *) names+=("${f:t}") ;; esac
      done
      git -C "$cfg" add -- $changed
      # Commit only these paths — anything else the user has staged stays staged
      if ! git_out=$(git -C "$cfg" commit -m "flake: update inputs ($(date +%Y-%m-%d))" -- $changed 2>&1); then
        printf '%s\n' "$git_out"
      fi
      if git_out=$(git -C "$cfg" push 2>&1); then
        printf "  →  pushed %s to %s  (%s)\n" "$(git -C "$cfg" rev-parse --short HEAD)" \
          "$(git -C "$cfg" branch --show-current)" "${(j:, :)names}"
      else
        printf '%s\n' "$git_out"
        echo "  ✗  push failed — committed locally, push manually"
      fi
    fi
  fi

  # ── Run summary ────────────────────────────────────────────────────────────
  if [[ -n $_NRU_START ]]; then
    local t=$(( EPOCHSECONDS - _NRU_START )) dl=${st[dl_mib]:-0}
    if (( dl == 0 ));      then dl="nothing downloaded"
    elif (( dl >= 1024 )); then dl=$(printf '%.1f GiB downloaded' $(( dl / 1024.0 )))
    else                        dl=$(printf '%.0f MiB downloaded' $dl); fi
    printf "  ⏱  %dm %02ds total · %s · %s built\n" $(( t / 60 )) $(( t % 60 )) "$dl" "${st[built]:-0}"
  fi

  # ── Disk check ─────────────────────────────────────────────────────────────
  local pcent avail
  read -r pcent avail <<< "$(df -h --output=pcent,avail /nix | tail -1)"
  if (( ${pcent%\%} > 90 )); then
    [[ $(_nru_menu "⚠" "/nix ${pcent} full ($avail free)" "G:GC now" "s:skip") == g ]] \
      && sudo nix-collect-garbage --delete-older-than 30d
  fi

  # ── Firmware check ─────────────────────────────────────────────────────────
  # Uses the metadata fwupd-refresh.timer already fetched; exit 0 = updates
  # available, 2 = none. Notice only — installing is left to the user.
  fwupdmgr get-updates --no-unreported-check --no-metadata-check </dev/null &>/dev/null \
    && printf "  ⚠  Firmware update available · please run: fwupdmgr update\n"

  # ── Reboot check ───────────────────────────────────────────────────────────
  # Booted vs current system: a new kernel, initrd or systemd only fully takes
  # effect after a reboot.
  local -a why
  local b c
  if [[ "$(readlink -f /run/booted-system/kernel)" != "$(readlink -f /run/current-system/kernel)" ]]; then
    why+=("kernel $(uname -r) → $(ls /run/current-system/kernel-modules/lib/modules/ 2>/dev/null | head -1)")
  elif [[ "$(readlink -f /run/booted-system/initrd)" != "$(readlink -f /run/current-system/initrd)" ]]; then
    why+=("initrd")
  fi
  b=$(readlink -f /run/booted-system/systemd); c=$(readlink -f /run/current-system/systemd)
  [[ "$b" != "$c" ]] && why+=("systemd ${${b:t}#*-systemd-} → ${${c:t}#*-systemd-}")

  if (( $#why )); then
    curl -s -o /dev/null --max-time 10 \
      -H "Title: Reboot Required — $(hostname)" \
      -H "Priority: high" \
      -H "Tags: warning,arrows_counterclockwise" \
      -d "Reboot needed: ${(j:, :)why}. Reboot when convenient." \
      "http://media-server:2586/nixos-updates" 2>/dev/null || true
    [[ $(_nru_menu "⚠" "Reboot needed · ${(j:, :)why}" "R:reboot now" "l:later") == r ]] && sudo reboot
  else
    if (( code == 4 )); then
      [[ $(_nru_menu "⚠" "Rebuild done · close terminal?" "Y:yes" "n:no") == y ]] && exit 0
    else
      [[ $(_nru_menu "✓" "Rebuild Clean · close terminal?" "Y:yes" "n:no") == y ]] && exit 0
    fi
  fi
  return 0
}

