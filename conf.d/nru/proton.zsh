# ===========================================================================
# conf.d/nru/proton.zsh — nru steps that bump the Proton builds
#
# Each Proton build is an inline pkgs.fetchzip in nixos-config
# modules/gaming/gaming.nix, pinned by a tag and a hash marked with
# "# proton-<name>-nru" and "# proton-<name>-hash" comments. These functions
# check GitHub for a newer release. Only the lock writer (_nru_is_lock_writer)
# downloads it, hashes it and rewrites both lines; the rebuild step then
# commits gaming.nix with flake.lock and other hosts get it on their next pull.
# nru runs them only when steam is installed (conf.d/nru/nru.zsh). Loaded like
# every conf.d/*/*.zsh file; there is no switch.
#
# All three take no arguments and always return 0; the result is one status
# row (current / available / bumped / warning). Shared flow:
#   1. read the current tag from gaming.nix; skip when _NRU_OFFLINE is set
#   2. GitHub API releases/latest → tag_name (curl -fsSL --max-time 15)
#   3. same tag → quiet row; not the lock writer → "available" row
#   4. download the asset in the background with a MiB progress row
#      (size from a HEAD request, curl -I)
#   5. nix store prefetch-file --hash-type sha256 --unpack → SRI hash of the
#      unpacked tree, the same hash fetchzip checks
#   6. sed both marked lines in gaming.nix; on any failure leave it untouched
# ===========================================================================

# _nru_update_proton_cachyos — Proton-CachyOS from CachyOS/proton-cachyos.
#   Tag      protonCachyosTag, e.g. cachyos-<ver>-<date>-slr (shown as <date>)
#   Asset    proton-<tag>-x86_64.tar.xz
#   Example  _nru_update_proton_cachyos
_nru_update_proton_cachyos() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-Cachy" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonCachyosTag = "\K[^"]+' "$gm")
  cur_s=${${current#cachyos-*-}%-slr}   # cachyos-11.0-20261005-slr → 20261005
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Latest release tag. The pipeline's status is jq's, not curl's: when curl
  # fails (offline, rate limit) jq gets empty input and still exits 0, so the
  # empty result is what signals failure.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${${latest#cachyos-*-}%-slr}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Lock writer only from here. Download in the background (&| = disowned,
  # exit code to a file read by _nru_wait_exit), redraw MiB done / total every
  # 0.2s, then hash the local file.
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

  # Tag and hash are written together, only once the hash is known, so the
  # module never holds a tag with the wrong hash.
  sed -i \
    -e "s|protonCachyosTag = \"[^\"]*\"; # proton-cachyos-nru|protonCachyosTag = \"${latest}\"; # proton-cachyos-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-cachyos-hash|hash = \"${hash}\"; # proton-cachyos-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

# _nru_update_proton_wineland — Proton Wineland from nanomatters/proton-salkim
# (the repo that publishes its release binaries).
#   Tag      protonWinelandTag, e.g. wineland-<ver>-<date> (shown without
#            "wineland-")
#   Asset    proton-<tag>-x86_64.tar.xz
#   Example  _nru_update_proton_wineland
_nru_update_proton_wineland() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-Wineland" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonWinelandTag = "\K[^"]+' "$gm")
  cur_s=${current#wineland-}   # wineland-11.0-20261103 → 11.0-20261103
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Latest release tag. The pipeline's status is jq's, not curl's: when curl
  # fails (offline, rate limit) jq gets empty input and still exits 0, so the
  # empty result is what signals failure.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/nanomatters/proton-salkim/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${latest#wineland-}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Lock writer only from here. Download in the background (&| = disowned,
  # exit code to a file read by _nru_wait_exit), redraw MiB done / total every
  # 0.2s, then hash the local file.
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

  # Tag and hash are written together, only once the hash is known, so the
  # module never holds a tag with the wrong hash.
  sed -i \
    -e "s|protonWinelandTag = \"[^\"]*\"; # proton-wineland-nru|protonWinelandTag = \"${latest}\"; # proton-wineland-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-wineland-hash|hash = \"${hash}\"; # proton-wineland-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

# _nru_update_proton_ge — GE-Proton from GloriousEggroll/proton-ge-custom,
# taken from the release tarball. Alternative: pkgs.proton-ge-bin from
# nixpkgs, which needs no tracker but follows nixpkgs' update pace.
#   Tag      protonGeTag, e.g. GE-Proton<major>-<build> (shown without
#            "GE-Proton")
#   Asset    <tag>-x86_64.tar.gz
#   Example  _nru_update_proton_ge
_nru_update_proton_ge() {
  local gm="$NIXOS_CONFIG/modules/gaming/gaming.nix" name="Proton-GE" icon=$_NRU_GH
  local current latest cur_s new_s url tmp size total got xf pid hash i=1

  current=$(grep -oP 'protonGeTag = "\K[^"]+' "$gm")
  cur_s=${current#GE-Proton}   # GE-Proton11-12 → 11-12
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  # Latest release tag. The pipeline's status is jq's, not curl's: when curl
  # fails (offline, rate limit) jq gets empty input and still exits 0, so the
  # empty result is what signals failure.
  latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null)
  if [[ -z $latest ]]; then _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping $cur_s"; return 0; fi
  new_s=${latest#GE-Proton}

  if [[ $latest == "$current" ]]; then _nru_quiet "$icon" "$name" "$cur_s"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$cur_s" "· $new_s available (Ryzen5900x will bump it)"; return 0
  fi

  # Lock writer only from here. Download in the background (&| = disowned,
  # exit code to a file read by _nru_wait_exit), redraw MiB done / total every
  # 0.2s, then hash the local file.
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

  # Tag and hash are written together, only once the hash is known, so the
  # module never holds a tag with the wrong hash.
  sed -i \
    -e "s|protonGeTag = \"[^\"]*\"; # proton-ge-nru|protonGeTag = \"${latest}\"; # proton-ge-nru|" \
    -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"; # proton-ge-hash|hash = \"${hash}\"; # proton-ge-hash|" \
    "$gm"
  _nru_ok "$icon" "$name" "$cur_s → $new_s"
}

