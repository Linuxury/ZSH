# ---------------------------------------------------------------------------
# nru shared state + helpers
#
# Rows for each update step go to /dev/tty so \r can redraw the same line;
# trees, raw dumps and summaries go to stdout.
# ---------------------------------------------------------------------------
zmodload zsh/datetime   # EPOCHSECONDS for timers
_NRU_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nru"   # last-failure.log, last-units.txt, last-packages.txt
_NRU_GH="󰊤"     # U+F02A4 nf-md-github (Nerd Fonts) — 2-cell wide
_NRU_NIX="󱄅"   # U+F1105 nf-linux-nixos (Nerd Fonts) — 2-cell wide (same as _NRU_GH)
_NRU_FP="󰏖"    # U+F03D6 nf-md-package_variant — same glyph fastfetch uses for flatpak count
# Colour roles. muted/head/err are palette slots (color8 / bold color4 / color1), so the
# terminal theme decides them; warn is a fixed gold because Noctalia's palette has no
# real yellow (its color3 is pale grey-cyan, indistinguishable from plain text).
_C_MUTED=$'\e[90m' _C_HEAD=$'\e[1;34m' _C_ERR=$'\e[31m' _C_WARN=$'\e[38;2;229;192;123m' _C_OFF=$'\e[0m'
# Group state; bare typeset keeps values across the silent re-source mid-run.
typeset -g _NRU_GRP _NRU_GRP_SHOWN _NRU_GRP_NOTE _NRU_GRP_HIDE _NRU_GRP_PREV _NRU_IND
_NRU_SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Only linuxury@Ryzen5900x writes shared state (flake.lock, proton bump, hash
# fixes) and pushes it — every other host just pulls. Two writers = guaranteed
# lock conflicts (ThinkPad stranded a lock commit 2026-09-27 that broke nru
# on 2026-10-10).
_nru_is_lock_writer() { [[ "$(whoami)" == linuxury && "$(hostname)" == Ryzen5900x ]] }

# Groups: _nru_group NAME DEFAULT-NOTE … _nru_group_end. A group prints its bold
# header only once a row has something to say; if none did, it collapses to one
# muted line. Blank lines go around expanded groups only (_NRU_GRP_PREV = last
# kind printed: exp/dim). With no group open the helpers print plain rows.
_nru_group() { _NRU_GRP=$1 _NRU_GRP_NOTE=$2 _NRU_GRP_SHOWN= _NRU_GRP_HIDE= _NRU_IND="  " }
_nru_group_end() {
  [[ -n $_NRU_GRP ]] || return 0
  if [[ -z $_NRU_GRP_SHOWN && -z $_NRU_GRP_HIDE ]]; then
    [[ $_NRU_GRP_PREV == exp ]] && printf "\n" >/dev/tty
    printf "  %s%-8s %s  ✓%s\n" "$_C_MUTED" "$_NRU_GRP" "$_NRU_GRP_NOTE" "$_C_OFF" >/dev/tty
    _NRU_GRP_PREV=dim
  fi
  _NRU_GRP= _NRU_IND=   # _nru_group resets the rest
}
_nru_hdr() {   # clears the spinner line, then prints the group header once
  [[ -n $_NRU_GRP && -z $_NRU_GRP_SHOWN ]] || return 0
  printf "\r\033[K" >/dev/tty
  [[ -n $_NRU_GRP_PREV ]] && printf "\n" >/dev/tty
  printf "  %s%s%s\n" "$_C_HEAD" "$_NRU_GRP" "$_C_OFF" >/dev/tty
  _NRU_GRP_SHOWN=1 _NRU_GRP_PREV=exp
}
_nru_hide() { _NRU_GRP_HIDE=1; printf "\r\033[K" >/dev/tty; }   # step is deliberately silent here

# Final row for a step:              _nru_row ICON NAME TEXT   (✗ red, ⚠ gold)
_nru_row() {
  local t=$3; _nru_hdr
  case $t in ✗*) t="$_C_ERR$t$_C_OFF" ;; ⚠*) t="$_C_WARN$t$_C_OFF" ;; esac
  printf "\r  %s%s  %-12s  %s\033[K\n" "$_NRU_IND" "$1" "$2" "$t" >/dev/tty
}
# Completed row with something to say: _nru_ok ICON NAME INFO [SUFFIX]
_nru_ok() { _nru_hdr; printf "\r  %s%s  %-12s  %s  ✓%s\033[K\n" "$_NRU_IND" "$1" "$2" "$3" "${4:+  $4}" >/dev/tty }
# Nothing to report: clears the spinner and leaves it to the group's muted line
# (NOTE replaces the group's default text). Outside a group it is a plain _nru_ok row.
#   _nru_quiet ICON NAME INFO [NOTE]
_nru_quiet() {
  [[ -n $_NRU_GRP ]] || { _nru_ok "$1" "$2" "$3"; return 0 }
  printf "\r\033[K" >/dev/tty
  [[ -n $4 ]] && _NRU_GRP_NOTE=$4
  return 0
}
_nru_offline() { _nru_quiet "$1" "$2" "⏭ skipped (offline)" "skipped (offline)" }   # _nru_offline ICON NAME
# Tree under a row, one arg per item
_nru_tree() {
  local i b
  for (( i = 1; i <= $#; i++ )); do
    b="├─"; (( i == $# )) && b="└─"
    printf "       %s%s %s\n" "$_NRU_IND" "$b" "${@[i]}"
  done
}

# _nru_wait_exit FILE — waits briefly for a background job's exit-code file,
# prints the code (1 if it never appeared) and removes the file.
_nru_wait_exit() {
  local r=0 code=1
  while [[ ! -f "$1" ]] && (( r++ < 50 )); do sleep 0.01; done
  [[ -f "$1" ]] && code=$(<"$1")
  rm -f "$1"
  print -r -- "$code"
}

# ---------------------------------------------------------------------------
# _nru_spin — runs a command in the background behind a spinner, for steps
# with no measurable progress (no fake bar). Elapsed time shows after 3s.
# Output goes to LOG; returns the command's exit code. Leaves the spinner on
# the line so the caller can overwrite it with its own final row (\r).
#
# Usage: _nru_spin ICON NAME TEXT LOG cmd [args...]
#   →  "  󰊤  Nixos-Config  ⠹ pulling…  4s"
# ---------------------------------------------------------------------------
_nru_spin() {
  local icon=$1 name=$2 text=$3 log=$4; shift 4
  local xf="$_NRU_CACHE/.exit.$$" t0=$EPOCHSECONDS el i=1
  mkdir -p "$_NRU_CACHE"; rm -f "$xf"

  # &| disowns immediately (no job notifications); exit code goes to a file
  # because wait cannot track a disowned pid in zsh.
  { "$@" >"$log" 2>&1; echo $? >"$xf" } &|
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    el=$(( EPOCHSECONDS - t0 ))
    printf "\r  %s%s  %-12s  %s %s…%s\033[K" "$_NRU_IND" "$icon" "$name" "$_NRU_SPIN[i]" "$text" \
      "${${el:#[012]}:+  ${el}s}" >/dev/tty
    sleep 0.1
    i=$(( i % 10 + 1 ))
  done

  return $(_nru_wait_exit "$xf")
}

# ---------------------------------------------------------------------------
# _nru_menu — one-line menu on /dev/tty; prints the chosen key (lowercase).
# The uppercase key is the default, picked by Enter.
#
# Usage: choice=$(_nru_menu "⚠" "Title" "S:Stash & pull" "d:discard & pull" "q:quit")
#   → "  ⚠  Title  ·   [S]tash & pull   [d]iscard & pull   [q]uit  › "
# ---------------------------------------------------------------------------
_nru_menu() {
  local sym=$1 title=$2 opt k l keys="" def="" line="" reply; shift 2
  for opt in "$@"; do
    k=${opt%%:*}; l=${opt#*:}
    [[ $k == [[:upper:]] ]] && def=${k:l}
    keys+=${k:l}
    if [[ ${l[1]:l} == ${k:l} ]]; then line+="   [$k]${l[2,-1]}"; else line+="   [$k] $l"; fi
  done
  while true; do
    printf "\n  %s  %s  ·%s  › " "$sym" "$title" "$line" >/dev/tty
    read -r reply </dev/tty
    reply=${${reply:l}[1]}
    [[ -z $reply ]] && reply=$def
    [[ -n $reply && $keys == *$reply* ]] && { print -r -- "$reply"; return 0 }
  done
}

# ---------------------------------------------------------------------------
# _nru_ticker — draws the live rebuild line at 10 Hz until killed.
#
# The awk filter never draws progress itself — it writes the current state
# ("eval" or "fetch|done|total|label" / "build|…") to a state file and this
# single background loop renders it with a spinner, plus elapsed time once one
# item has taken 10s+. An empty state file means "don't draw" (awk clears it
# and waits 0.15s before printing a normal line, so the two never collide).
# ---------------------------------------------------------------------------
_nru_ticker() {
  local statef=$1 st kind cnt tot lbl last="" since=$EPOCHSECONDS el f pct sfx icon e="" i=1
  while true; do
    st=$(<"$statef") 2>/dev/null
    if [[ $st == eval ]]; then
      printf "\r  %s  Evaluating…\033[K" "$_NRU_SPIN[i]" >/dev/tty
    elif [[ -n $st ]]; then
      IFS='|' read -r kind cnt tot lbl <<< "$st"
      [[ ${lbl%% \[*} != "$last" ]] && { last=${lbl%% \[*}; since=$EPOCHSECONDS }   # per package, not per [n/m] step
      el=$(( EPOCHSECONDS - since )); sfx=""
      (( el >= 10 )) && sfx=$(printf '  %dm%02ds' $(( el / 60 )) $(( el % 60 )))
      (( tot > 0 )) || tot=1
      pct=$(( cnt * 100 / tot )); f=$(( cnt * 20 / tot ))
      [[ $kind == fetch ]] && icon="⬇" || icon="⚒"
      printf "\r  %s  %-12s  [%s%s]  %3d%%  %-30s %s%s\033[K" "$icon" "$cnt/$tot" \
        "${(l:f::■:)e}" "${(l:20-f::□:)e}" "$pct" "$lbl" "$_NRU_SPIN[i]" "$sfx" >/dev/tty
    fi
    sleep 0.1
    i=$(( i % 10 + 1 ))
  done
}

