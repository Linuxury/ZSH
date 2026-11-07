# ---------------------------------------------------------------------------
# _nru_update_craft_apps — checks the storytold Craft apps for new releases.
# Tags come from git ls-remote (no GitHub API rate limit). Only the lock
# writer bumps pkgs/craft-apps/package.nix (version + hash from upstream's
# SHA256SUMS.txt, always written together); other hosts report and pull it.
# ---------------------------------------------------------------------------
_nru_craft_latest() {   # "<app> <version>" per app, all in parallel
  local a
  for a; do
    { print -r -- "$a ${$(GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote --tags --refs \
        "https://github.com/storytold/$a" 2>/dev/null | grep -oE 'v[0-9]+(\.[0-9]+)*$' | sort -V | tail -1)#v}" } &
  done
  wait
}
_nru_craft_sums() {     # "<app> <version> <sha256 hex>" per app@version, all in parallel
  local av
  for av; do
    { print -r -- "${av% *} ${av#* } $(curl -fsSL --max-time 15 \
        "https://github.com/storytold/${av% *}/releases/download/v${av#* }/SHA256SUMS.txt" 2>/dev/null \
        | grep -F "${av% *}-${av#* }-linux-x86_64.tar.gz" | cut -d' ' -f1)" } &
  done
  wait
}
_nru_update_craft_apps() {
  local pkg="$NIXOS_CONFIG/pkgs/craft-apps/package.nix" name="Craft Apps" icon=$_NRU_GH
  local log="$_NRU_CACHE/craft.log" a v h sri w=0
  local -A cur new
  local -a moved rows

  for a v in $(sed -nE 's/^\s+([a-z]+craft)\s+= \{ version = "([^"]+)".*/\1 \2/p' "$pkg"); do cur[$a]=$v; done
  (( $#cur )) || return 0
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$icon" "$name"; return 0; fi

  _nru_spin "$icon" "$name" "checking $#cur apps" "$log" _nru_craft_latest ${(k)cur}
  for a v in $(<"$log"); do new[$a]=$v; done
  if (( ! ${#${(M)${(v)new}:#?*}} )); then
    _nru_row "$icon" "$name" "⚠ GitHub unreachable · keeping current versions"; return 0
  fi
  for a in ${(ok)cur}; do
    [[ -n ${new[$a]} && ${new[$a]} != ${cur[$a]} ]] || continue
    [[ $(print -l ${cur[$a]} ${new[$a]} | sort -V | tail -1) == ${new[$a]} ]] || continue   # never downgrade
    moved+=($a); (( ${#a} > w )) && w=${#a}
  done

  if (( ! $#moved )); then _nru_quiet "$icon" "$name" "all $#cur current"; return 0; fi
  if ! _nru_is_lock_writer; then
    _nru_ok "$icon" "$name" "$(( $#cur - $#moved )) of $#cur current" "· $#moved available (Ryzen5900x will bump them)"
    return 0
  fi

  # Version and hash are written together, only once the hash is known.
  local -a pairs; for a in $moved; do pairs+=("$a ${new[$a]}"); done
  _nru_spin "$icon" "$name" "hashing $#moved apps" "$log" _nru_craft_sums $pairs
  local -i n=0
  for a in $moved; do
    h=$(awk -v a=$a -v v=${new[$a]} '$1 == a && $2 == v { print $3 }' "$log")
    sri=${h:+$(nix hash convert --hash-algo sha256 --to sri "$h" 2>/dev/null)}
    if [[ -z $sri ]]; then
      rows+=("$(printf "⚠ %-${w}s  checksum unavailable · keeping %s" "$a" "${cur[$a]}")"); continue
    fi
    sed -i -E "s|^(\s+$a\s+= \{ version = \")[^\"]+(\"; hash = \")[^\"]+|\1${new[$a]}\2$sri|" "$pkg"
    rows+=("$(printf "%-${w}s  %s → %s" "$a" "${cur[$a]}" "${new[$a]}")"); (( n++ ))
  done
  _nru_ok "$icon" "$name" "$n of $#cur updated"
  _nru_tree "${rows[@]}"
}

# _nru_craft_unpackaged — reports storytold *craft repos missing from
# package.nix (a new app needs a suite + a build check, so never auto-added).
# Lock writer only: one GitHub API call, shared 60/h budget. Silent on failure.
_nru_craft_unpackaged() {
  _nru_is_lock_writer && [[ -z $_NRU_OFFLINE ]] || return 0
  local -a have new
  have=($(sed -nE 's/^\s+([a-z]+craft)\s+= \{.*/\1/p' "$NIXOS_CONFIG/pkgs/craft-apps/package.nix"))
  # artcraft = the engine itself, not a Craft app
  new=($(curl -fsSL --max-time 15 "https://api.github.com/orgs/storytold/repos?per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.archived | not) | .name | select(test("^[a-z]+craft$") and . != "artcraft")' 2>/dev/null))
  new=(${new:|have})
  (( $#new )) || return 0
  _nru_row "$_NRU_GH" "Craft (new)" "🆕 ${(j:, :)new} · not packaged — add to pkgs/craft-apps/package.nix"
}

