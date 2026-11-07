# ---------------------------------------------------------------------------
# _nru_update_claude_desktop — bumps pkgs/claude-desktop/package.nix to the
# newest build in Anthropic's apt index. Version and SHA256 come from the same
# Packages file (nothing is downloaded) and are always written together.
# Only the lock writer bumps; other hosts report and pull it.
# ---------------------------------------------------------------------------
_nru_claude_latest() {   # "<version> <sha256 hex>" of the newest amd64 build
  curl -fsSL --max-time 15 https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages \
    | awk '/^Version:/ { v = $2 } /^SHA256:/ { print v, $2 }' | sort -V | tail -1
}
# Bump the VSCodium Open VSX extensions (lock writer only; scripts/vscodium-ext-bump does the work).
_nru_update_vscodium_ext() {
  local name="VSCodium ext" icon=$_NRU_NIX log="$_NRU_CACHE/vscodium-ext.log"
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi
  if ! _nru_spin "$icon" "$name" "checking" "$log" "$NIXOS_CONFIG/scripts/vscodium-ext-bump"; then
    _nru_row "$icon" "$name" "⚠ bump failed · keeping pins"; sed -E "s/^/       $_NRU_IND/" "$log" | tail -2; return 0
  fi
  local res=$(tail -1 "$log")
  if [[ $res == "all current" ]]; then _nru_quiet "$icon" "$name" "$res"; else _nru_ok "$icon" "$name" "$res"; fi
}

# Bump the pinned ZenNotes image tag (lock writer only; scripts/zennotes-bump does the work).
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

# Bump Media-Server's pinned Plex (lock writer only; scripts/plex-bump does the work).
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

