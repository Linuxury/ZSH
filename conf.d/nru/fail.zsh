# ---------------------------------------------------------------------------
# _nru_fail_summary — turns a failed rebuild log into a short explanation.
#
# Sets _NRU_FAIL_KIND (hash | hash-stale | hash-manual | build | config |
# download | disk | unknown) and, for hash kinds, _NRU_FIX_PKG/_ATTR/_HASH,
# which _nru_rebuild uses to pick sensible menu options.
# ---------------------------------------------------------------------------
_nru_fail_summary() {
  local log=$1 drv spec got dep pkg="" attr="" msg loc nixlog
  _NRU_FAIL_KIND=unknown; _NRU_FIX_PKG=""; _NRU_FIX_ATTR=""; _NRU_FIX_HASH=""
  echo ""

  if grep -q 'hash mismatch in fixed-output derivation' "$log"; then
    drv=$(grep -m1 -oP "fixed-output derivation '/nix/store/[a-z0-9]{32}-\K[^']+(?=\.drv')" "$log")
    spec=$(grep -m1 -oP 'specified:\s+\Ksha256-\S+' "$log")
    got=$(grep -m1 -oP 'got:\s+\Ksha256-\S+' "$log")
    dep=$(( $(grep -c 'error: Cannot build' "$log") - 1 ))
    case $drv in
      *-pnpm-deps)           attr=pnpmDeps;  pkg=${drv%-pnpm-deps} ;;
      *-npm-deps)            attr=npmDeps;   pkg=${drv%-npm-deps} ;;
      *-cargo-deps|*-vendor) attr=cargoDeps; pkg=${${drv%-cargo-deps}%-vendor} ;;
      *-go-modules)          attr=goModules; pkg=${drv%-go-modules} ;;
    esac
    pkg=${pkg%%-[0-9]*}   # "foo-1.2.3" → "foo"
    _NRU_FIX_PKG=$pkg; _NRU_FIX_ATTR=$attr; _NRU_FIX_HASH=$got

    if [[ -n $pkg ]] && grep -qF "$spec" "$NIXOS_CONFIG/pkgs/hash-fixes.nix" 2>/dev/null; then
      _NRU_FAIL_KIND=hash-stale
      printf "  ✗  %s · our hash fix is now stale (nixpkgs fixed it upstream)\n" "$pkg"
    else
      # Only offer [F]ix when the attribute really exists and carries the
      # hash nix complained about — otherwise the override would miss.
      if [[ -n $attr ]] && [[ "$(nix eval --raw "$NIXOS_CONFIG#nixosConfigurations.$(hostname).pkgs.$pkg.$attr.outputHash" 2>/dev/null)" == "$spec" ]]; then
        _NRU_FAIL_KIND=hash
      else
        _NRU_FAIL_KIND=hash-manual
      fi
      printf "  ✗  %s · dependency hash mismatch (nixpkgs bug, not your config)\n" "${pkg:-$drv}"
      printf "       got %s\n" "$got"
      if [[ $_NRU_FAIL_KIND == hash ]]; then
        printf "       fix: [F] adds an override to pkgs/hash-fixes.nix\n"
      else
        printf "       fix: override the package's outputHash in an overlay\n"
      fi
    fi
    (( dep > 0 )) && printf "       + %d packages that depend on it also failed\n" "$dep"

  elif grep -q 'No space left on device' "$log"; then
    _NRU_FAIL_KIND=disk
    printf "  ✗  disk full · /nix has %s free · GC frees old generations\n" "$(df -h --output=avail /nix | tail -1 | tr -d ' ')"

  elif grep -qE 'unable to download|Could not resolve host|Couldn.t resolve host|Connection timed out|Failed to connect' "$log"; then
    _NRU_FAIL_KIND=download
    printf "  ✗  download failed · %s\n" "$(grep -m1 -oE "unable to download '[^']+'|Could(n.t| not) resolve host[^;]*" "$log")"
    printf "       retry usually fixes this\n"

  elif drv=$(grep -m1 -oP "builder for '/nix/store/[a-z0-9]{32}-\K[^']+(?=\.drv')" "$log"); then
    _NRU_FAIL_KIND=build
    nixlog=$(grep -m1 -oP "nix log \K/nix/store/\S+\.drv" "$log")
    printf "  ✗  build failed · %s\n" "$drv"
    grep -E '^\s+> ' "$log" | tail -5 | sed 's/^\s*>/       │/'
    [[ -n $nixlog ]] && printf "       full log: nix log %s\n" "$nixlog"

  elif ! grep -q 'error: Cannot build' "$log" && grep -qE '^\s*error:' "$log"; then
    _NRU_FAIL_KIND=config
    msg=$(grep -E '^\s*error: \S' "$log" | tail -1 | sed -E 's/^\s*error: //; s/ Definition values:$//')
    loc=$(grep -oP "(at |In \`)/nix/store/[a-z0-9]{32}-source/\K[^:']+(:\d+)?" "$log" | tail -1)
    printf "  ✗  config error · %s\n" "$msg"
    [[ -n $loc ]] && printf "       at %s\n" "$loc"

  else
    printf "  ✗  rebuild failed\n"
    grep -E '^\s*error:' "$log" | grep -vE 'Cannot build|Build failed due to failed dependency' \
      | head -5 | sed -E 's/^\s*/       /'
  fi

  printf "  full output: %s\n" "${log/#$HOME/~}"
}

# ---------------------------------------------------------------------------
# _nru_hash_fix — adds (kind hash) or removes (kind hash-stale) the entry for
# _NRU_FIX_PKG in pkgs/hash-fixes.nix. One entry per line, file ends "}".
# ---------------------------------------------------------------------------
_nru_hash_fix() {
  local f="$NIXOS_CONFIG/pkgs/hash-fixes.nix"
  sed -i "/^  ${_NRU_FIX_PKG} = /d" "$f"
  if [[ $_NRU_FAIL_KIND == hash ]]; then
    sed -i "\$i\\  ${_NRU_FIX_PKG} = { attr = \"${_NRU_FIX_ATTR}\"; hash = \"${_NRU_FIX_HASH}\"; added = \"$(date +%F)\"; };" "$f"
    printf "  ✎  added %s → pkgs/hash-fixes.nix · rebuilding…\n\n" "$_NRU_FIX_PKG"
  else
    printf "  ✎  removed %s from pkgs/hash-fixes.nix · rebuilding…\n\n" "$_NRU_FIX_PKG"
  fi
}

