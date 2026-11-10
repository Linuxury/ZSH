# _nru_update_proton_cachyos — checks GitHub for a new Proton-CachyOS release.
# Only the lock writer bumps the inline fetchzip in modules/gaming/gaming.nix
# (committed with flake.lock); other hosts just report it and get it on pull.
# nixpkgs has no CachyOS-Proton package under any name (checked), so this
# tracker stays; GE-Proton comes from nixpkgs (pkgs.proton-ge-bin).
# ---------------------------------------------------------------------------
_nru_update_proton_cachyos() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-Cachy" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonCachyosTag = "\K[^"]+' "$gm")
  cur_s=${${current#cachyos-*-}%-slr}   # cachyos-11.0-20261005-slr → 20261005
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Pipe status is jq's, not curl's — offline or rate-limited curl hands jq
  # empty input and jq still exits 0, so test the result, not the exit code.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${${latest#cachyos-*-}%-slr}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Download with real progress, then hash the local file.
  url="https://github.com/CachyOS/proton-cachyos/releases/download/${latest}/proton-${latest}-x86_64.tar.xz"
  tmp="$_NRU_CACHE/proton-${latest}.tar.xz"; xf="$_NRU_CACHE/.exit.$$"
  size=$(curl -fsSIL --max-time 15 "$url" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9')
  total=${size:+$(( size / 1048576 ))}
  rm -f "$xf" "$tmp"
  { curl -fsSL -o "$tmp" "$url"; echo $? >"$xf" } &|
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    got=$(( $(stat -c %s "$tmp" 2>/dev/null || echo 0) / 1048576 ))
    printf "\r  %s%s  %-12s  ⬇ downloading %s · %d/%s MiB  %s\033[K" \
      "$_NRU_IND" "$icon" "$name" "$new_s" "$got" "${total:-?}" "$_NRU_SPIN[i]" >/dev/tty
    sleep 0.2
    i=$(( i % 10 + 1 ))
  done
  if (( $(_nru_wait_exit "$xf") == 0 )); then
    _nru_spin "$icon" "$name" "hashing $new_s" "$_NRU_CACHE/proton.log" \
      nix store prefetch-file --hash-type sha256 --unpack "file://$tmp"
    hash=$(grep -m1 -oP 'sha256-[A-Za-z0-9+/=]+' "$_NRU_CACHE/proton.log")
  fi
  rm -f "$tmp"
  if [[ -z $hash ]]; then
    _nru_row "$icon" "$name" "⚠ download failed · keeping $cur_s, module untouched"; return 0
  fi

  # Tag and hash are written together, only once the hash is known.
  sed -i \
    -e "s|protonCachyosTag = \"[^\"]*\"; # proton-cachyos-nru|protonCachyosTag = \"${latest}\"; # proton-cachyos-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-cachyos-hash|hash = \"${hash}\"; # proton-cachyos-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

# _nru_update_proton_ge — checks GitHub for a new GE-Proton release.
# Only the lock writer bumps the inline fetchzip in modules/gaming/gaming.nix
# (committed with flake.lock); other hosts just report it and get it on pull.
# GE-Proton comes from the GitHub tarball (nixpkgs' proton-ge-bin lags).
# _nru_update_proton_wineland — checks GitHub for a new Proton Wineland release.
# Only the lock writer bumps the inline fetchzip in modules/gaming/gaming.nix
# (committed with flake.lock); other hosts just report it and get it on pull.
# Binaries are published only by the author's repo nanomatters/proton-salkim.
# ---------------------------------------------------------------------------
_nru_update_proton_wineland() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-Wineland" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonWinelandTag = "\K[^"]+' "$gm")
  cur_s=${current#wineland-}   # wineland-11.0-20261103 → 11.0-20261103
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Pipe status is jq's, not curl's — offline or rate-limited curl hands jq
  # empty input and jq still exits 0, so test the result, not the exit code.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/nanomatters/proton-salkim/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${latest#wineland-}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Download with real progress, then hash the local file.
  url="https://github.com/nanomatters/proton-salkim/releases/download/${latest}/proton-${latest}-x86_64.tar.xz"
  tmp="$_NRU_CACHE/proton-${latest}.tar.xz"; xf="$_NRU_CACHE/.exit.$$"
  size=$(curl -fsSIL --max-time 15 "$url" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9')
  total=${size:+$(( size / 1048576 ))}
  rm -f "$xf" "$tmp"
  { curl -fsSL -o "$tmp" "$url"; echo $? >"$xf" } &|
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    got=$(( $(stat -c %s "$tmp" 2>/dev/null || echo 0) / 1048576 ))
    printf "\r  %s%s  %-12s  ⬇ downloading %s · %d/%s MiB  %s\033[K" \
      "$_NRU_IND" "$icon" "$name" "$new_s" "$got" "${total:-?}" "$_NRU_SPIN[i]" >/dev/tty
    sleep 0.2
    i=$(( i % 10 + 1 ))
  done
  if (( $(_nru_wait_exit "$xf") == 0 )); then
    _nru_spin "$icon" "$name" "hashing $new_s" "$_NRU_CACHE/proton.log" \
      nix store prefetch-file --hash-type sha256 --unpack "file://$tmp"
    hash=$(grep -m1 -oP 'sha256-[A-Za-z0-9+/=]+' "$_NRU_CACHE/proton.log")
  fi
  rm -f "$tmp"
  if [[ -z $hash ]]; then
    _nru_row "$icon" "$name" "⚠ download failed · keeping $cur_s, module untouched"; return 0
  fi

  # Tag and hash are written together, only once the hash is known.
  sed -i \
    -e "s|protonWinelandTag = \"[^\"]*\"; # proton-wineland-nru|protonWinelandTag = \"${latest}\"; # proton-wineland-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-wineland-hash|hash = \"${hash}\"; # proton-wineland-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

# _nru_update_proton_ge — checks GitHub for a new GE-Proton release.
# Only the lock writer bumps the inline fetchzip in modules/gaming/gaming.nix
# (committed with flake.lock); other hosts just report it and get it on pull.
# GE-Proton comes from the GitHub tarball (nixpkgs' proton-ge-bin lags).
# ---------------------------------------------------------------------------
_nru_update_proton_ge() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-GE" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonGeTag = "\K[^"]+' "$gm")
  cur_s=${current#GE-Proton}   # GE-Proton11-12 → 11-12
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Pipe status is jq's, not curl's — offline or rate-limited curl hands jq
  # empty input and jq still exits 0, so test the result, not the exit code.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${latest#GE-Proton}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Download with real progress, then hash the local file.
  url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${latest}/${latest}-x86_64.tar.gz"
  tmp="$_NRU_CACHE/proton-${latest}.tar.gz"; xf="$_NRU_CACHE/.exit.$$"
  size=$(curl -fsSIL --max-time 15 "$url" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9')
  total=${size:+$(( size / 1048576 ))}
  rm -f "$xf" "$tmp"
  { curl -fsSL -o "$tmp" "$url"; echo $? >"$xf" } &|
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    got=$(( $(stat -c %s "$tmp" 2>/dev/null || echo 0) / 1048576 ))
    printf "\r  %s%s  %-12s  ⬇ downloading %s · %d/%s MiB  %s\033[K" \
      "$_NRU_IND" "$icon" "$name" "$new_s" "$got" "${total:-?}" "$_NRU_SPIN[i]" >/dev/tty
    sleep 0.2
    i=$(( i % 10 + 1 ))
  done
  if (( $(_nru_wait_exit "$xf") == 0 )); then
    _nru_spin "$icon" "$name" "hashing $new_s" "$_NRU_CACHE/proton.log" \
      nix store prefetch-file --hash-type sha256 --unpack "file://$tmp"
    hash=$(grep -m1 -oP 'sha256-[A-Za-z0-9+/=]+' "$_NRU_CACHE/proton.log")
  fi
  rm -f "$tmp"
  if [[ -z $hash ]]; then
    _nru_row "$icon" "$name" "⚠ download failed · keeping $cur_s, module untouched"; return 0
  fi

  # Tag and hash are written together, only once the hash is known.
  sed -i \
    -e "s|protonGeTag = \"[^\"]*\"; # proton-ge-nru|protonGeTag = \"${latest}\"; # proton-ge-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-ge-hash|hash = \"${hash}\"; # proton-ge-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

