# ===========================================================================
# conf.d/nru/00-ui.zsh — shared state and terminal helpers for nru
#
# Loaded before the other nru files ("00-" sorts first); they all call what is
# defined here: the cache directory, icons, colours, the group/row printing
# helpers, the background-command spinner (_nru_spin), the one-line menu
# (_nru_menu) and the rebuild progress ticker (_nru_ticker). Sourcing it only
# defines variables and functions; nothing runs until nru, nr or nrt is called.
# To turn nru off, remove the conf.d/nru/ folder from the checkout.
#
# Output routing: each step's row goes to /dev/tty so "\r" can redraw the same
# line; trees, raw dumps and summaries go to stdout.
# ===========================================================================

# zsh/datetime module — provides $EPOCHSECONDS (integer seconds since the
# epoch), used for step timers. Same module also offers $EPOCHREALTIME (float)
# and the strftime builtin.
zmodload zsh/datetime   # EPOCHSECONDS for timers

# Cache directory for nru's logs and scratch files.
#   XDG_CACHE_HOME     base directory when set; otherwise ~/.cache
#   <step>.log         output of one update step (git.log, inputs.log, flatpak.log, …)
#   last-failure.log   full log of the last failed rebuild
#   last-packages.txt  package diff (nvd) of the last rebuild that changed the system
#   last-units.txt     systemd units started/stopped/restarted by the last switch
#   .exit.<pid>        exit code of a running _nru_spin command (removed after reading)
#   .ticker.<pid>      state file of the running rebuild ticker (removed after the build)
_NRU_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nru"   # last-failure.log, last-units.txt, last-packages.txt

# Row icons — Nerd Font glyphs, so the terminal font must be a Nerd Font to
# draw them. Names are from the Nerd Fonts glyph table; to change one, replace
# the character between the quotes with any other single glyph.
#   _NRU_GH   U+F02A4  nf-md-github           the git pull step
#   _NRU_NIX  U+F1105  nf-md-nix              the flake inputs step
#   _NRU_FP   U+F03D6  nf-md-package_variant  the Flatpak step (also the
#                                              glyph the fastfetch config uses for its package-count line)
_NRU_GH="󰊤"     # U+F02A4 nf-md-github (Nerd Fonts)
_NRU_NIX="󱄅"   # U+F1105 nf-md-nix (Nerd Fonts)
_NRU_FP="󰏖"    # U+F03D6 nf-md-package_variant — same glyph fastfetch uses for flatpak count
# Colour roles, as raw ANSI SGR escape sequences ($'…' turns \e into a real ESC).
#   _C_MUTED  \e[90m                bright black (palette slot 8): dim secondary text
#   _C_HEAD   \e[1;34m              bold + blue (palette slot 4): group headers
#   _C_ERR    \e[31m                red (palette slot 1): rows starting with ✗
#   _C_WARN   \e[38;2;229;192;123m  fixed 24-bit gold (#E5C07B): rows starting with ⚠
#   _C_OFF    \e[0m                 reset all attributes
# MUTED/HEAD/ERR use palette slots, so the terminal theme picks the actual
# colour. WARN is a fixed RGB value so it stays yellow whatever the theme maps
# slot 3 to. Alternatives: \e[33m (theme yellow, slot 3), \e[93m (bright
# yellow, slot 11), or any \e[38;2;R;G;Bm value.
_C_MUTED=$'\e[90m' _C_HEAD=$'\e[1;34m' _C_ERR=$'\e[31m' _C_WARN=$'\e[38;2;229;192;123m' _C_OFF=$'\e[0m'
# Group state (see "Groups" below). A bare `typeset -g NAME` declares the
# variable without assigning it, so a value already set survives the silent
# re-source of zshrc that nru performs mid-run (nru.zsh).
#   _NRU_GRP        name of the open group; empty when none is open
#   _NRU_GRP_NOTE   text of the group's collapsed one-line summary
#   _NRU_GRP_SHOWN  1 once the group's header has been printed
#   _NRU_GRP_HIDE   1 once a step chose to print nothing (_nru_hide)
#   _NRU_GRP_PREV   what the last group printed: "exp" (header + rows) or "dim"
#                   (collapsed line); decides where blank lines go. nru clears
#                   it at the start of a run.
#   _NRU_IND        extra indent for rows: two spaces inside a group, empty outside
typeset -g _NRU_GRP _NRU_GRP_SHOWN _NRU_GRP_NOTE _NRU_GRP_HIDE _NRU_GRP_PREV _NRU_IND

# Spinner frames (Braille dots), read as $_NRU_SPIN[i] with i running 1..10.
# _nru_spin and _nru_ticker advance i every 0.1 s (10 Hz) and wrap with
# `i % 10 + 1`, so a replacement set (e.g. ASCII: - \ | /) needs 10 frames or
# the wrap constant changed.
_NRU_SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# _nru_is_lock_writer — true only for user linuxury on host Ryzen5900x.
# That one account on that one host owns the shared state: it updates
# flake.lock, bumps pinned versions and hashes, and pushes the result; every
# other host only pulls. Two writers would produce conflicting lock commits.
# Used by _nru_inputs_bar and nru to decide which update steps run.
# To move the role, change the user and host names in the test below.
# Example: _nru_is_lock_writer && echo "this host updates the lock"
_nru_is_lock_writer() { [[ "$(whoami)" == linuxury && "$(hostname)" == Ryzen5900x ]] }

# Groups — a titled section of the nru output:
#   _nru_group NAME DEFAULT-NOTE   open a group
#   … step helpers (_nru_row, _nru_ok, _nru_quiet, _nru_hide, _nru_offline) …
#   _nru_group_end                 close it
# A group prints its bold header only once a step has something to say; if no
# step did, it collapses to one muted "NAME  NOTE  ✓" line. Blank lines go
# around expanded groups only (_NRU_GRP_PREV records the last kind printed).
# With no group open the helpers print plain rows.
# Example: _nru_group Flatpak "up to date"; _nru_flatpak_bar; _nru_group_end

# _nru_group NAME DEFAULT-NOTE — open a group. NAME is the header text;
# DEFAULT-NOTE is the text of the collapsed line (a step can replace it via
# _nru_quiet). Clears the group's shown/hidden flags and sets the row indent.
_nru_group() { _NRU_GRP=$1 _NRU_GRP_NOTE=$2 _NRU_GRP_SHOWN= _NRU_GRP_HIDE= _NRU_IND="  " }
# _nru_group_end — close the open group (no arguments; no-op if none is open).
# If no step printed and none called _nru_hide, prints the collapsed line:
# muted NAME padded to 8 columns, the note, and a ✓. Nothing is printed when a
# step hid itself, so a group whose only step is silent disappears entirely.
_nru_group_end() {
  [[ -n $_NRU_GRP ]] || return 0
  if [[ -z $_NRU_GRP_SHOWN && -z $_NRU_GRP_HIDE ]]; then
    [[ $_NRU_GRP_PREV == exp ]] && printf "\n" >/dev/tty
    printf "  %s%-8s %s  ✓%s\n" "$_C_MUTED" "$_NRU_GRP" "$_NRU_GRP_NOTE" "$_C_OFF" >/dev/tty
    _NRU_GRP_PREV=dim
  fi
  _NRU_GRP= _NRU_IND=   # _nru_group resets the rest
}
# _nru_hdr — print the open group's bold header, once (no arguments). Called
# by every row helper before it prints. First erases the spinner line
# ("\r" = back to column 0, "\033[K" = erase to end of line), then adds a
# blank line if an earlier group was printed.
_nru_hdr() {   # clears the spinner line, then prints the group header once
  [[ -n $_NRU_GRP && -z $_NRU_GRP_SHOWN ]] || return 0
  printf "\r\033[K" >/dev/tty
  [[ -n $_NRU_GRP_PREV ]] && printf "\n" >/dev/tty
  printf "  %s%s%s\n" "$_C_HEAD" "$_NRU_GRP" "$_C_OFF" >/dev/tty
  _NRU_GRP_SHOWN=1 _NRU_GRP_PREV=exp
}
# _nru_hide — erase the step's spinner line and print nothing, not even the
# group's collapsed line. For steps that do not apply on this host
# (e.g. Flatpak when Flathub is not configured).
_nru_hide() { _NRU_GRP_HIDE=1; printf "\r\033[K" >/dev/tty; }   # step is deliberately silent here

# _nru_row ICON NAME TEXT — the final row of a step, printed over its spinner.
#   ICON  a glyph ($_NRU_GH, $_NRU_NIX, $_NRU_FP, …)
#   NAME  label, padded to 12 columns
#   TEXT  result; starting with ✗ colours the text red, starting with ⚠ gold
# Example: _nru_row "$_NRU_GH" "Nixos-Config" "✗ pull failed"
_nru_row() {
  local t=$3; _nru_hdr
  case $t in ✗*) t="$_C_ERR$t$_C_OFF" ;; ⚠*) t="$_C_WARN$t$_C_OFF" ;; esac
  printf "\r  %s%s  %-12s  %s\033[K\n" "$_NRU_IND" "$1" "$2" "$t" >/dev/tty
}
# _nru_ok ICON NAME INFO [SUFFIX] — a completed step with something to report:
# "ICON  NAME  INFO  ✓" followed by the optional SUFFIX. ICON and NAME as in
# _nru_row.
# Example: _nru_ok "$_NRU_NIX" "Flake Inputs" "3 of 11 updated"
_nru_ok() { _nru_hdr; printf "\r  %s%s  %-12s  %s  ✓%s\033[K\n" "$_NRU_IND" "$1" "$2" "$3" "${4:+  $4}" >/dev/tty }
# _nru_quiet ICON NAME INFO [NOTE] — a step with nothing to report.
# Inside a group: erases the spinner line and leaves the output to the group's
# collapsed line; NOTE, if given, replaces that line's default text.
# Outside a group: prints a plain _nru_ok row using INFO (NOTE is unused).
# Example: _nru_quiet "$_NRU_GH" "Nixos-Config" "up to date"
_nru_quiet() {
  [[ -n $_NRU_GRP ]] || { _nru_ok "$1" "$2" "$3"; return 0 }
  printf "\r\033[K" >/dev/tty
  [[ -n $4 ]] && _NRU_GRP_NOTE=$4
  return 0
}
# _nru_offline ICON NAME — a step skipped because the pull found no network
# (_NRU_OFFLINE set). Quiet: the group's line reads "skipped (offline)".
# Example: [[ -n $_NRU_OFFLINE ]] && { _nru_offline "$_NRU_FP" "Flatpak"; return 0 }
_nru_offline() { _nru_quiet "$1" "$2" "⏭ skipped (offline)" "skipped (offline)" }   # _nru_offline ICON NAME
# _nru_tree ITEM… — print a tree under the previous row, one argument per
# line: "├─" for each item, "└─" for the last. Goes to stdout.
# Example: _nru_tree "nixpkgs  05-11 → 05-12" "agenix  new"
#            ├─ nixpkgs  05-11 → 05-12
#            └─ agenix  new
_nru_tree() {
  local i b
  for (( i = 1; i <= $#; i++ )); do
    b="├─"; (( i == $# )) && b="└─"
    printf "       %s%s %s\n" "$_NRU_IND" "$b" "${@[i]}"
  done
}

# _nru_wait_exit FILE — read the exit code a background job left in FILE.
# Polls every 0.01 s for up to about 0.5 s for the file to appear, prints its
# contents (1 if it never appeared) and removes it. Used by _nru_spin.
# Example: rc=$(_nru_wait_exit "$_NRU_CACHE/.exit.$$")
_nru_wait_exit() {
  local r=0 code=1
  while [[ ! -f "$1" ]] && (( r++ < 50 )); do sleep 0.01; done
  [[ -f "$1" ]] && code=$(<"$1")
  rm -f "$1"
  print -r -- "$code"
}

# ---------------------------------------------------------------------------
# _nru_spin — run a command in the background behind a spinner, for steps with
# no measurable progress (so no progress bar). Stdout and stderr of the command
# go to LOG; returns the command's exit code. Leaves the spinner on the line
# so the caller overwrites it with its own final row ("\r").
#
# Usage: _nru_spin ICON NAME TEXT LOG cmd [args...]
#   ICON  glyph shown at the line start
#   NAME  label, padded to 12 columns
#   TEXT  what is happening, shown after the spinner frame (e.g. "pulling")
#   LOG   file that receives the command's output (overwritten)
#   cmd   the command and its arguments
# The line redraws every 0.1 s: "  <icon>  NAME  ⠹ TEXT…  4s". Elapsed seconds
# appear once the command has run 3 s or longer.
# Example: _nru_spin "$_NRU_GH" "Nixos-Config" "pulling" "$log" git -C "$cfg" pull --ff-only
# ---------------------------------------------------------------------------
_nru_spin() {
  local icon=$1 name=$2 text=$3 log=$4; shift 4
  local xf="$_NRU_CACHE/.exit.$$" t0=$EPOCHSECONDS el i=1
  mkdir -p "$_NRU_CACHE"; rm -f "$xf"

  # `&|` starts the group in the background and disowns it (zsh also spells it
  # `&!`), so zsh prints no "[1] 1234" / "done" job notices. The exit code goes
  # to a file because `wait` refuses a disowned pid ("not a child of this
  # shell", status 127). The file name carries the shell's pid ($$) so
  # concurrent shells do not collide.
  { "$@" >"$log" 2>&1; echo $? >"$xf" } &|
  local pid=$!

  # `kill -0` sends no signal; it succeeds while the process still exists.
  # The elapsed field is empty for 0-2 s, then "  Ns".
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
# _nru_menu — one-line menu read from /dev/tty. Prints the chosen key,
# lowercase, on stdout (so call it inside $(…)); always returns 0.
#
# Usage: _nru_menu SYMBOL TITLE KEY:LABEL...
#   SYMBOL  glyph at the line start (⚠ for a choice, ✗ for an error)
#   TITLE   short heading
#   KEY:LABEL  one per choice. KEY is one letter; an uppercase KEY marks the
#              default, taken when Enter is pressed. If LABEL starts with the
#              key letter it is shown as "[S]tash"; otherwise "[k] keep".
#              With no uppercase KEY, Enter alone re-prompts.
# Input: the first character typed, case-insensitive. Anything that is not
# one of the keys re-prompts.
# Example: choice=$(_nru_menu "⚠" "Title" "S:Stash & pull" "d:discard & pull" "q:quit")
#   → "  ⚠  Title  ·   [S]tash & pull   [d]iscard & pull   [q]uit  › "
#   then  [[ $choice == s ]] && …
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
# _nru_ticker — draw the live rebuild line at 10 Hz until killed.
#
# Usage: _nru_ticker STATE-FILE &|      (the caller keeps $! and kills it)
# The awk filter in _nix_fetch_filter never draws progress itself; it writes
# the current state to STATE-FILE and this single background loop renders it:
#   eval                   "<spinner>  Evaluating…"
#   fetch|DONE|TOTAL|LABEL   ⬇  DONE/TOTAL  [■■■□□…]  NN%  LABEL  <spinner>
#   build|DONE|TOTAL|LABEL   ⚒  (same layout)
#   (empty file)           draw nothing — the filter empties it and waits
#                          0.15 s before printing a normal line, so the two
#                          never write over each other
# The bar is 20 cells (■ done, □ left). Elapsed time ("  1m05s") is appended
# once the same package has taken 10 s or more; the timer restarts when the
# label changes, ignoring a trailing " [n/m]" step counter.
# Example: echo "fetch|3|10|hello-2.12" > "$statef"; _nru_ticker "$statef" &|
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

