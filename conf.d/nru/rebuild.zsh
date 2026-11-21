# ===========================================================================
# conf.d/nru/rebuild.zsh — the rebuild step of nru
#
# Defines _nru_rebuild, called by nru (conf.d/nru/nru.zsh) after its update
# steps and by nru's Ctrl+C retry menu. Loaded like every conf.d/*/*.zsh file
# by zshrc; there is no switch. To drop it, nru must stop calling it first.
# ===========================================================================

# Files nru updates in nixos-config: [p]revious lock checks and restores them,
# and the lock writer commits and pushes them. One list, so all three agree.
typeset -ga _NRU_PINNED=(
  flake.lock
  modules/gaming/gaming.nix
  pkgs/hash-fixes.nix
  pkgs/craft-apps/package.nix
  pkgs/claude-desktop/package.nix
  hosts/Media-Server/plex.json
  modules/services/zennotes/zennotes.json
  modules/development/editors/vscodium/extensions.json
)

# _nru_rebuild — switch this host to the flake in $NIXOS_CONFIG, then report.
# A separate function so a retry repeats only the rebuild, not nru's git pull
# and input updates.
#   Arguments  none (host = $(hostname), flake = $NIXOS_CONFIG)
#   Returns    0 after a switch; 1 when the user picks [q]uit in the failure
#              menu. Exits the shell when the user answers yes to
#              "close terminal?".
#   Sets       _NRU_ON_PREV=1 when the build ran on the restored previous lock
#   Example    _nru_rebuild
# Steps: rebuild (with a failure menu and retry loop), verdict line, auto-update
# markers, push of pinned files (lock writer only), run summary, /nix disk
# check, firmware check, reboot check.
_nru_rebuild() {
  local cfg=$NIXOS_CONFIG code choice moved key
  local -a keys opts
  _NRU_ON_PREV=""

  # Rebuild + failure menu, repeated until a switch succeeds or the user quits.
  #   _nixos_run          runs the command behind the progress filter, saves the
  #                       log, and on failure sets _NRU_FAIL_KIND (via
  #                       _nru_fail_summary in fail.zsh)
  #   switch              build, activate and make it the boot default
  #                       (alternatives: boot = only at next boot, test = activate
  #                       without a boot entry, dry-build = only show what builds)
  #   -L                  --print-build-logs; the filter reads these lines to
  #                       name the package that is building
  #   --no-link           don't leave a ./result symlink in the current directory
  #   --flake "$cfg#host" build nixosConfigurations.<hostname> from the repo
  # Exit codes: 0 = switched, 4 = switched but some units failed to start
  # (both end the loop), 130 = Ctrl+C.
  while true; do
    _nixos_run sudo nixos-rebuild switch -L --no-link --flake "$cfg#$(hostname)"
    code=$?
    (( code == 0 || code == 4 )) && break
    (( code == 130 )) && _NRU_FAIL_KIND=interrupted

    # [p]revious lock is offered only when this run changed a pinned file
    # (uncommitted diff vs HEAD): flake.lock plus the pins nru's updaters bump
    # (Proton tags, craft apps, Claude desktop, Plex, ZenNotes, VSCodium ext).
    #
    # Menu keys per failure kind (from _nru_fail_summary):
    #   f  fix: hash = add an override to pkgs/hash-fixes.nix, hash-stale =
    #      remove ours (_nru_hash_fix in fail.zsh)
    #   p  previous lock: git restore the pinned files, rebuild on HEAD's pins
    #   r  retry the same rebuild
    #   l  log: open the saved failure log in less, then show the menu again
    #   g  garbage-collect generations older than 30 days, then retry
    #   q  quit (returns 1)
    moved=""
    git -C "$cfg" diff --quiet HEAD -- "${_NRU_PINNED[@]}" 2>/dev/null || moved=p
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
    # Build the "key:label" list for _nru_menu. The first entry gets an
    # uppercase key and label, which marks it as the default picked by Enter.
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
      p) git -C "$cfg" restore "${_NRU_PINNED[@]}" 2>/dev/null
         _NRU_ON_PREV=1
         printf "  ↺  restored flake.lock (nixpkgs %s) · rebuilding…\n\n" \
           "$(date -d @"$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified' "$cfg/flake.lock")" +%F)" ;;
      g) sudo nix-collect-garbage --delete-older-than 30d ;;
      r) ;;
      q) return 1 ;;
    esac
  done

  # ── Verdict ────────────────────────────────────────────────────────────────
  # One line: no changes / switched with N unit failures (exit 4) / success.
  #   st                  key=value pairs from last-run.stats, written by the
  #                       filter (fetched, dl_mib, built, failed_units)
  #   _NIXOS_LAST_GEN     generation number, set by _nixos_run
  #   _NIXOS_SWITCH_TIME  activation time, set by _nixos_run
  #   _NIXOS_CHANGED      0 when the new system equals the running one
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

  # Auto-update markers (read by nixos-config modules/services/auto-update):
  #   /etc/nixos-last-update-time   epoch of the last update; the scheduled run
  #                                 skips if it is under 20h old (file is 0666)
  #   /run/user/$UID/nixos-update-done  stops the session-start update from
  #                                 running again this boot
  date +%s > /etc/nixos-last-update-time 2>/dev/null || true
  touch /run/user/$UID/nixos-update-done 2>/dev/null || true

  # ── Push shared state (lock writer only) ───────────────────────────────────
  # Only the lock writer (_nru_is_lock_writer in 00-ui.zsh) commits and pushes
  # the pinned files that changed; other hosts pull them on their next nru.
  #   changed  pinned files with uncommitted changes (flake.lock, hash fixes,
  #            updater pins)
  #   names    short display names for the "pushed" line
  # Commit message: "flake: update inputs (YYYY-MM-DD)". Git output is hidden
  # on success and printed in full on failure.
  if _nru_is_lock_writer; then
    local git_out f
    local -a changed names
    changed=(${(f)"$(git -C "$cfg" status --porcelain -- "${_NRU_PINNED[@]}" | cut -c4-)"})
    if (( $#changed )); then
      for f in $changed; do
        case $f in modules/gaming/gaming.nix) names+=("gaming module") ;; pkgs/craft-apps/package.nix) names+=("craft apps") ;; pkgs/claude-desktop/package.nix) names+=("claude desktop") ;; hosts/Media-Server/plex.json) names+=("plex") ;; modules/services/zennotes/zennotes.json) names+=("zennotes") ;; modules/development/editors/vscodium/extensions.json) names+=("vscodium ext") ;; *) names+=("${f:t}") ;; esac
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
  # Shown only when nru set _NRU_START: total time since nru started, data
  # downloaded (MiB, or GiB from 1024 MiB) and number of derivations built.
  if [[ -n $_NRU_START ]]; then
    local t=$(( EPOCHSECONDS - _NRU_START )) dl=${st[dl_mib]:-0}
    if (( dl == 0 ));      then dl="nothing downloaded"
    elif (( dl >= 1024 )); then dl=$(printf '%.1f GiB downloaded' $(( dl / 1024.0 )))
    else                        dl=$(printf '%.0f MiB downloaded' $dl); fi
    printf "  ⏱  %dm %02ds total · %s · %s built\n" $(( t / 60 )) $(( t % 60 )) "$dl" "${st[built]:-0}"
  fi

  # ── Disk check ─────────────────────────────────────────────────────────────
  # Above 90% use on /nix, offer garbage collection (Enter = GC now).
  #   nix-collect-garbage --delete-older-than 30d  delete generations older than
  #   30 days, then unreachable store paths. Alternatives: -d (all old
  #   generations), --max-freed BYTES (stop after freeing that much),
  #   --dry-run (only show what would go).
  local pcent avail
  read -r pcent avail <<< "$(df -h --output=pcent,avail /nix | tail -1)"
  if (( ${pcent%\%} > 90 )); then
    [[ $(_nru_menu "⚠" "/nix ${pcent} full ($avail free)" "G:GC now" "s:skip") == g ]] \
      && sudo nix-collect-garbage --delete-older-than 30d
  fi

  # ── Firmware check ─────────────────────────────────────────────────────────
  # Notice only; installing is left to the user (fwupdmgr update).
  #   get-updates            list available updates for all devices
  #   --no-unreported-check  skip the prompt about unreported update history
  #   --no-metadata-check    use the metadata fwupd-refresh.timer already
  #                          fetched; don't ask to refresh it
  # Exit status: 0 = updates available, 2 = nothing to do.
  fwupdmgr get-updates --no-unreported-check --no-metadata-check </dev/null &>/dev/null \
    && printf "  ⚠  Firmware update available · please run: fwupdmgr update\n"

  # ── Reboot check ───────────────────────────────────────────────────────────
  # Compares /run/booted-system with /run/current-system: a new kernel, initrd
  # or systemd only fully takes effect after a reboot.
  #   why   reasons, e.g. "kernel A → B", "initrd", "systemd A → B"
  # If a reboot is needed: send an ntfy push to the nixos-updates topic on
  # media-server (headers: Title, Priority = min|low|default|high|max, Tags =
  # emoji short codes), then offer "reboot now" (Enter) or "later".
  # If not: offer to close the terminal (Enter = yes).
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

