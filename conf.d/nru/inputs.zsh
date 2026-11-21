# ===========================================================================
# conf.d/nru/inputs.zsh — the "Flake Inputs" step of nru
#
# Updates every flake input on the lock-writer host and lists which ones moved.
# Other hosts keep the flake.lock they pulled. nru (nru.zsh) calls it right
# after the git pull. Revisions and dates come from flake.lock itself (before
# vs after), never parsed from nix's output.
# The step is on while that call is in nru.zsh; remove the call to turn it off.
# ===========================================================================

# _nru_lock_inputs — print one line per root input of $NIXOS_CONFIG/flake.lock:
#   <input> <rev> <lastModified>
# lastModified is a Unix timestamp. Inputs without a git rev (tarball or path
# inputs) print their narHash in the rev column. Read with jq -r (raw strings).
# Example: _nru_lock_inputs | grep '^nixpkgs '
_nru_lock_inputs() {   # "<input> <rev> <lastModified>" per root input
  jq -r '.nodes as $n | $n.root.inputs | to_entries[]
         | ($n[.value].locked) as $l | "\(.key) \($l.rev // $l.narHash) \($l.lastModified)"' \
    "$NIXOS_CONFIG/flake.lock"
}

# ---------------------------------------------------------------------------
# _nru_inputs_bar — update all flake inputs and show which ones moved.
# Takes no arguments; reads $NIXOS_CONFIG; always returns 0 — a failed update
# keeps the current lock and nru carries on.
# Steps:
#   1. snapshot revisions and timestamps from flake.lock
#   2. not the lock-writer host → report the lock as pulled, stop
#   3. offline (_NRU_OFFLINE set) → skipped row, stop
#   4. nix flake update --flake "$NIXOS_CONFIG", behind a spinner (log:
#      inputs.log). With no input names it updates every input; `--flake`
#      selects the flake directory. On failure flake.lock is restored from
#      HEAD and the row says why: GitHub's rate limit, or the last "error:"
#      line of the log.
#   5. diff the new lock against the snapshot → "N of M updated" plus a tree,
#      one line per moved input:  "<input>  <old> → <new>  <rev, 7 chars>"
#      Dates show as MM-DD, or HH:MM when old and new fall on the same day;
#      an input new to the lock shows "new"; inputs without a git rev show no hash.
# ---------------------------------------------------------------------------
_nru_inputs_bar() {
  local name="Flake Inputs" log="$_NRU_CACHE/inputs.log" k r t m w=0 od
  local -A old_rev old_ts
  local -a moved rows

  while read -r k r t; do old_rev[$k]=$r; old_ts[$k]=$t; done < <(_nru_lock_inputs)

  # Only the lock-writer host (_nru_is_lock_writer) updates inputs; every other
  # host builds exactly the lock it just pulled. That keeps versions identical
  # everywhere and avoids GitHub API calls from the other hosts: unauthenticated
  # GitHub API requests are limited to 60 per hour per IP address, and every
  # machine behind one home connection shares that budget.
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
      # nix prints several "error:" lines and the first is often just a
      # header; the last one carries the actual message.
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
    # Pick the date format: "new" for an input not in the old lock; HH:MM when
    # old and new fall on the same day (a date alone would show no change);
    # MM-DD otherwise. `date -d @N` reads a Unix timestamp, +FORMAT prints it.
    if [[ -z $od ]]; then od=new; t=$(date -d @$t +%m-%d)
    elif [[ $(date -d @$od +%F) == $(date -d @$t +%F) ]]; then od=$(date -d @$od +%H:%M); t=$(date -d @$t +%H:%M)
    else od=$(date -d @$od +%m-%d); t=$(date -d @$t +%m-%d); fi
    rows+=("$(printf "%-${w}s  %s → %s  %s" "$k" "$od" "$t" "$r")")
  done
  _nru_ok "$_NRU_NIX" "$name" "$#moved of ${#old_rev} updated"
  _nru_tree "${rows[@]}"
}

