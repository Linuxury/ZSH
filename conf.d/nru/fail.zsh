# ===========================================================================
# conf.d/nru/fail.zsh — explain a failed rebuild and apply the hash fix
#
# _nixos_run (run.zsh) calls _nru_fail_summary on the saved failure log;
# _nru_rebuild (rebuild.zsh) reads the kind it sets to choose menu options and
# calls _nru_hash_fix for [f]ix. Loaded like every conf.d/*/*.zsh file; there
# is no switch.
# ===========================================================================

# _nru_fail_summary — print a short explanation of a failed rebuild log and
# classify it. The first matching check wins:
#   hash         fixed-output hash mismatch; the package attribute exists and
#                carries the hash nix expected, so [f]ix can override it
#   hash-stale   mismatch on a hash pkgs/hash-fixes.nix supplied: nixpkgs has
#                since fixed it, so our override must go
#   hash-manual  mismatch [f]ix cannot target (unknown attribute or hash)
#   disk         "No space left on device"; shows free space on /nix
#   download     DNS, timeout or connection errors while fetching
#   build        a builder failed; shows its last 5 log lines + "nix log" path
#   config       evaluation error; shows the message and file:line in the repo
#   unknown      anything else; shows up to 5 error lines
#   Arguments  $1  path to the rebuild log
#   Sets       _NRU_FAIL_KIND, and for hash kinds _NRU_FIX_PKG (package name),
#              _NRU_FIX_ATTR (pnpmDeps | npmDeps | cargoDeps | goModules),
#              _NRU_FIX_HASH (the hash nix got)
#   Example    _nru_fail_summary "$_NRU_CACHE/last-failure.log"
_nru_fail_summary() {
  local log=$1 drv spec got dep pkg="" attr="" msg loc nixlog
  _NRU_FAIL_KIND=unknown; _NRU_FIX_PKG=""; _NRU_FIX_ATTR=""; _NRU_FIX_HASH=""
  echo ""

  # Hash mismatch: drv = derivation name, spec/got = expected/actual hash,
  # dep = how many dependent builds failed with it. The drv suffix names the
  # fetcher attribute; the package name drops that suffix and the version.
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

# _nru_hash_fix — edit nixos-config pkgs/hash-fixes.nix (read by the
# hash-fixes overlay in flake.nix) for the package _nru_fail_summary found.
#   kind hash        replace any entry for _NRU_FIX_PKG with
#                    <pkg> = { attr = "<attr>"; hash = "<sri>"; added = "<date>"; };
#                    inserted before the closing "}"
#   kind hash-stale  delete the entry for _NRU_FIX_PKG
#   Arguments  none; uses _NRU_FAIL_KIND and _NRU_FIX_PKG/_ATTR/_HASH
#   Needs      one entry per line and "}" as the last line (sed edits by line)
#   Example    _nru_hash_fix
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

