# ---------------------------------------------------------------------------
# _nru_inputs_bar — updates every flake input; shows which ones moved.
# Dates/revs come from flake.lock itself (before vs after), never parsed from
# nix's output. A failed update keeps the current lock and carries on.
# ---------------------------------------------------------------------------
_nru_lock_inputs() {   # "<input> <rev> <lastModified>" per root input
  jq -r '.nodes as $n | $n.root.inputs | to_entries[]
         | ($n[.value].locked) as $l | "\(.key) \($l.rev // $l.narHash) \($l.lastModified)"' \
    "$NIXOS_CONFIG/flake.lock"
}

_nru_inputs_bar() {
  local name="Flake Inputs" log="$_NRU_CACHE/inputs.log" k r t m w=0 od
  local -A old_rev old_ts
  local -a moved rows

  while read -r k r t; do old_rev[$k]=$r; old_ts[$k]=$t; done < <(_nru_lock_inputs)

  # Only the lock writer updates inputs; every other host builds exactly the
  # lock it just pulled. Same versions everywhere, and no GitHub API calls
  # from them (60/hour per IP, shared by every machine behind the home IP —
  # Media-Server hit it on 2026-10-13 once nru updated all 11 inputs).
  if ! _nru_is_lock_writer; then
    _nru_quiet "$_NRU_NIX" "$name" "nixpkgs $(date -d @${old_ts[nixpkgs]} +%m-%d) · lock from Ryzen5900x" "lock from Ryzen5900x"
    return 0
  fi
  if [[ -n $_NRU_OFFLINE ]]; then _nru_offline "$_NRU_NIX" "$name"; return 0; fi

  if ! _nru_spin "$_NRU_NIX" "$name" "updating ${#old_rev} inputs" "$log" nix flake update --flake "$NIXOS_CONFIG"; then
    git -C "$NIXOS_CONFIG" restore flake.lock 2>/dev/null
    if grep -q 'rate limit exceeded' "$log"; then
      _nru_row "$_NRU_NIX" "$name" "⚠ GitHub rate limit · keeping current lock (nixpkgs $(date -d @${old_ts[nixpkgs]} +%F))"
    else
      # nix's first "error:" line is often bare; the real message is the last one
      _nru_row "$_NRU_NIX" "$name" "⚠ update failed · keeping current lock (nixpkgs $(date -d @${old_ts[nixpkgs]} +%F))"
      grep -E '^\s*error: \S' "$log" | tail -1 | sed -E "s/^\s*/       $_NRU_IND/"
    fi
    return 0
  fi

  while read -r k r t; do
    [[ ${old_rev[$k]} == "$r" ]] && continue
    moved+=("$k|${old_ts[$k]}|$t|$r")
    (( ${#k} > w )) && w=${#k}
  done < <(_nru_lock_inputs)

  if (( ! $#moved )); then _nru_quiet "$_NRU_NIX" "$name" "up to date"; return 0; fi
  for m in $moved; do
    IFS='|' read -r k od t r <<< "$m"
    [[ $r == sha256-* ]] && r= || r=${r:0:7}   # narHash (no rev): no hash shown
    # Same day on both sides says nothing — show the times instead.
    if [[ -z $od ]]; then od=new; t=$(date -d @$t +%m-%d)
    elif [[ $(date -d @$od +%F) == $(date -d @$t +%F) ]]; then od=$(date -d @$od +%H:%M); t=$(date -d @$t +%H:%M)
    else od=$(date -d @$od +%m-%d); t=$(date -d @$t +%m-%d); fi
    rows+=("$(printf "%-${w}s  %s → %s  %s" "$k" "$od" "$t" "$r")")
  done
  _nru_ok "$_NRU_NIX" "$name" "$#moved of ${#old_rev} updated"
  _nru_tree "${rows[@]}"
}

