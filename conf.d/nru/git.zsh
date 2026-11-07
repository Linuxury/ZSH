# ---------------------------------------------------------------------------
# _nru_git_bar — pulls latest nixos-config (fast-forward only).
# Failures are named, and the fixable ones get a menu:
#   local changes → stash / discard / keep · diverged → rebase / keep
#   offline → rebuild the local config anyway (sets _NRU_OFFLINE)
# ---------------------------------------------------------------------------
_nru_git_bar() {
  local cfg=$NIXOS_CONFIG log="$_NRU_CACHE/git.log" before after n out
  _NRU_OFFLINE=""

  # nru regenerates flake.lock every run; a leftover local bump (or one staged
  # by a failed push) would block the pull. Say so when something is discarded.
  if ! git -C "$cfg" diff --quiet HEAD -- flake.lock 2>/dev/null; then
    printf "  %s↺  discarded local flake.lock changes (nru regenerates it)%s\n" "$_C_MUTED" "$_C_OFF" >/dev/tty
    git -C "$cfg" restore --staged --worktree flake.lock 2>/dev/null
  fi

  before=$(git -C "$cfg" rev-parse --short HEAD)
  if _nru_spin "$_NRU_GH" "Nixos-Config" "pulling" "$log" git -C "$cfg" pull --ff-only; then
    after=$(git -C "$cfg" rev-parse --short HEAD)
    if [[ $before == "$after" ]]; then
      _nru_quiet "$_NRU_GH" "Nixos-Config" "up to date"
    else
      n=$(git -C "$cfg" rev-list --count "$before..$after")
      _nru_ok "$_NRU_GH" "Nixos-Config" "$n commit${${n:#1}:+s}  $before → $after"
    fi
    return 0
  fi

  out=$(<"$log")
  case $out in
    *"would be overwritten by"*)
      _nru_git_local_changes; return ;;
    *"Not possible to fast-forward"*|*"diverging branches"*)
      _nru_git_diverged; return ;;
    *"Permission denied (publickey)"*|*"Host key verification failed"*)
      _nru_row "$_NRU_GH" "Nixos-Config" "✗ SSH auth failed · check your ~/.ssh key is added to GitHub"
      _nru_git_skip_or_quit; return ;;
    *"Could not resolve"*|*"Network is unreachable"*|*"Connection timed out"*|*"Connection refused"*|*"Temporary failure in name resolution"*)
      _nru_row "$_NRU_GH" "Nixos-Config" "⚠ offline"
      [[ $(_nru_menu "⚠" "Offline · rebuild local config anyway?" "Y:yes" "n:no") == y ]] || return 1
      _NRU_OFFLINE=1; echo ""; return 0 ;;
  esac

  _nru_row "$_NRU_GH" "Nixos-Config" "✗ pull failed"
  printf '%s\n' "$out"
  return 1
}

_nru_git_local_changes() {
  local cfg=$NIXOS_CONFIG f add del
  local -a files items
  # git lists the blocking files tab-indented under the "would be overwritten" line
  files=(${(f)"$(awk '/would be overwritten by/ {f=1; next} f && /^\t/ {sub(/^\t/, ""); print; next} {f=0}' "$_NRU_CACHE/git.log")"})
  for f in $files; do
    read -r add del _ <<< "$(git -C "$cfg" diff --numstat HEAD -- "$f")"
    items+=("$f${add:+   (+$add −$del)}")
  done
  _nru_row "$_NRU_GH" "Nixos-Config" "✗ local changes block the pull"
  _nru_tree "${items[@]}"

  case $(_nru_menu "⚠" "Local Changes" "S:Stash & pull" "d:discard & pull" "k:keep, skip pull" "q:quit") in
    s) git -C "$cfg" stash push -u -q -m "nru $(date '+%F %H:%M')" || return 1
       printf "  ↓  stashed as \"nru %s\" (git stash pop to restore)\n" "$(date '+%F %H:%M')"
       _nru_git_bar; return ;;
    d) for f in $files; do
         if git -C "$cfg" ls-files --error-unmatch -- "$f" &>/dev/null; then
           git -C "$cfg" checkout -q HEAD -- "$f"
         else
           rm -f -- "$cfg/$f"
         fi
       done
       _nru_git_bar; return ;;
    k) _nru_row "$_NRU_GH" "Nixos-Config" "⏭ kept local changes, skipped pull"; return 0 ;;
    q) return 1 ;;
  esac
}

_nru_git_diverged() {
  local cfg=$NIXOS_CONFIG ahead behind
  git -C "$cfg" fetch -q 2>/dev/null
  read -r ahead behind <<< "$(git -C "$cfg" rev-list --left-right --count 'HEAD...@{u}')"
  _nru_row "$_NRU_GH" "Nixos-Config" "✗ diverged · $ahead local / $behind remote commits"

  case $(_nru_menu "⚠" "Diverged" "R:Rebase local onto remote" "k:keep, skip pull" "q:quit") in
    r) if _nru_spin "$_NRU_GH" "Nixos-Config" "rebasing" "$_NRU_CACHE/git.log" git -C "$cfg" pull --rebase; then
         _nru_ok "$_NRU_GH" "Nixos-Config" "rebased $ahead local onto $behind remote"
         return 0
       fi
       git -C "$cfg" rebase --abort 2>/dev/null
       _nru_row "$_NRU_GH" "Nixos-Config" "✗ rebase conflict · rebase aborted, repo unchanged"
       _nru_git_skip_or_quit; return ;;
    k) _nru_row "$_NRU_GH" "Nixos-Config" "⏭ skipped pull · rebuilding local config"; return 0 ;;
    q) return 1 ;;
  esac
}

_nru_git_skip_or_quit() {
  [[ $(_nru_menu "⚠" "Pull Failed" "k:keep, skip pull" "Q:quit") == k ]] || return 1
  _nru_row "$_NRU_GH" "Nixos-Config" "⏭ skipped pull · rebuilding local config"
}

