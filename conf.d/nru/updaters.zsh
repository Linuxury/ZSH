# ===========================================================================
# conf.d/nru/updaters.zsh — nru steps that bump single pinned packages
#
# Each step checks one pin in nixos-config and prints one status row
# (current / bumped / available / warning); all return 0. The rebuild step
# commits changed pins on the lock writer. Which hosts run which step is set in
# conf.d/nru/nru.zsh: Claude desktop where it is installed (or on the lock
# writer), the rest on the lock writer only. Skipped when _NRU_OFFLINE is set.
# Loaded like every conf.d/*/*.zsh file; there is no switch.
# ===========================================================================

# _nru_claude_latest — "<version> <sha256 hex>" of the newest amd64 build in
# Anthropic's apt Packages index (nothing is downloaded; 15s timeout).
#   Example  read -r ver sha < <(_nru_claude_latest)
_nru_claude_latest() {   # "<version> <sha256 hex>" of the newest amd64 build
  curl -fsSL --max-time 15 https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages \
    | awk '/^Version:/ { v = $2 } /^SHA256:/ { print v, $2 }' | sort -V | tail -1
}
# The next four steps run a script in nixos-config/scripts that rewrites its pin
# file; the step only shows the result. On script failure: warning row plus the
# script's last 2 log lines, pin kept.
#   Arguments  none
#   Example    _nru_update_zennotes

# _nru_update_vscodium_ext — Open VSX extensions in
# modules/development/editors/vscodium/extensions.json (scripts/vscodium-ext-bump;
# entries with a "hold" reason are skipped).
_nru_update_vscodium_ext() {
  local name="VSCodium ext" icon=$_NRU_NIX log="$_NRU_CACHE/vscodium-ext.log"
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi
  if ! _nru_spin "$icon" "$name" "checking" "$log" "$NIXOS_CONFIG/scripts/vscodium-ext-bump"; then
    _nru_row "$icon" "$name" "⚠ bump failed · keeping pins"; sed -E "s/^/       $_NRU_IND/" "$log" | tail -2; return 0
  fi
  local res=$(tail -1 "$log")
  if [[ $res == "all current" ]]; then _nru_quiet "$icon" "$name" "$res"; else _nru_ok "$icon" "$name" "$res"; fi
}

# _nru_update_zennotes — ZenNotes image tag in
# modules/services/zennotes/zennotes.json, newest x.y.z on Docker Hub
# (scripts/zennotes-bump).
_nru_update_zennotes() {
  local pin="$NIXOS_CONFIG/modules/services/zennotes/zennotes.json" name="ZenNotes" icon=$_NRU_NIX
  local log="$_NRU_CACHE/zennotes.log" cur new
  cur=$(jq -r .version "$pin")
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi
  if ! _nru_spin "$icon" "$name" "checking" "$log" "$NIXOS_CONFIG/scripts/zennotes-bump"; then
    _nru_row "$icon" "$name" "⚠ bump failed · keeping $cur"; sed -E "s/^/       $_NRU_IND/" "$log" | tail -2; return 0
  fi
  new=$(jq -r .version "$pin")
  if [[ $new == $cur ]]; then _nru_quiet "$icon" "$name" "$cur current"; else _nru_ok "$icon" "$name" "$cur → $new"; fi
}

# _nru_update_mailcraft — MailCraft release in pkgs/mailcraft/mailcraft.json,
# newest on GitHub, hash from the release SHA256SUMS.txt
# (scripts/mailcraft-bump).
_nru_update_mailcraft() {
  local pin="$NIXOS_CONFIG/pkgs/mailcraft/mailcraft.json" name="MailCraft" icon=$_NRU_NIX
  local log="$_NRU_CACHE/mailcraft.log" cur new
  cur=$(jq -r .version "$pin")
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi
  if ! _nru_spin "$icon" "$name" "checking" "$log" "$NIXOS_CONFIG/scripts/mailcraft-bump"; then
    _nru_row "$icon" "$name" "⚠ bump failed · keeping $cur"; sed -E "s/^/       $_NRU_IND/" "$log" | tail -2; return 0
  fi
  new=$(jq -r .version "$pin")
  if [[ $new == $cur ]]; then _nru_quiet "$icon" "$name" "$cur current"; else _nru_ok "$icon" "$name" "$cur → $new"; fi
}

# _nru_update_plex — Media-Server's Plex in hosts/Media-Server/plex.json
# (scripts/plex-bump, called with no argument = Plex Pass beta channel;
# alternative: "public" for the public release). Shown without the build
# suffix after the last "-".
_nru_update_plex() {
  local pin="$NIXOS_CONFIG/hosts/Media-Server/plex.json" name="Plex" icon=$_NRU_NIX
  local log="$_NRU_CACHE/plex.log" cur new
  cur=$(jq -r .version "$pin")
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi
  if ! _nru_spin "$icon" "$name" "checking beta" "$log" "$NIXOS_CONFIG/scripts/plex-bump"; then
    _nru_row "$icon" "$name" "⚠ bump failed · keeping ${cur%-*}"; sed -E "s/^/       $_NRU_IND/" "$log" | tail -2; return 0
  fi
  new=$(jq -r .version "$pin")
  if [[ $new == $cur ]]; then _nru_quiet "$icon" "$name" "${cur%-*} current"; else _nru_ok "$icon" "$name" "${cur%-*} → ${new%-*}"; fi
}

# _nru_update_claude_desktop — bump pkgs/claude-desktop/package.nix to the
# newest build from _nru_claude_latest. Never downgrades. Version and SRI hash
# are written together; only the lock writer writes them, other hosts show
# "available" and get the bump on their next pull.
#   Arguments  none
#   Example    _nru_update_claude_desktop
_nru_update_claude_desktop() {
  local pkg="$NIXOS_CONFIG/pkgs/claude-desktop/package.nix" name="Claude" icon=$_NRU_FP
  local log="$_NRU_CACHE/claude.log" cur new h sri
  cur=$(grep -oP '^\s+version = "\K[^"]+' "$pkg")
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  _nru_spin "$icon" "$name" "checking" "$log" _nru_claude_latest
  read -r new h < "$log"
  if [[ -z $new || -z $h ]]; then _nru_row "$icon" "$name" "⚠ apt index unreachable · keeping $cur"; return 0; fi
  # never downgrade
  if [[ $new == $cur || $(print -l $cur $new | sort -V | tail -1) != $new ]]; then
    _nru_quiet "$icon" "$name" "$cur current"; return 0
  fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur" "· $new available (Ryzen5900x will bump it)"; return 0
  fi

  sri=$(nix hash convert --hash-algo sha256 --to sri "$h" 2>/dev/null)
  if [[ -z $sri ]]; then _nru_row "$icon" "$name" "⚠ checksum unreadable · keeping $cur"; return 0; fi
  sed -i -E "s|^(\s+version = \")[^\"]+|\1$new|; s|^(\s+hash = \")[^\"]+|\1$sri|" "$pkg"
  _nru_ok "$icon" "$name" "$cur → $new"
}

