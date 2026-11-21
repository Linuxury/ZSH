# ===========================================================================
# conf.d/herdr/team.zsh — herdr-team: a lead + four workers Claude team
#
# Defines the herdr-team command, which lays out a team of Claude Code
# sessions in herdr-app (one lead tab, one "Workers" tab split 2x2) and
# brings it back after a reboot. Loaded with every other conf.d/*/*.zsh file
# by zshrc; it does nothing until called. Needs claude, jq, herdr-app and hc.
#
#   herdr-team app      with herdr-app open: build the team space, or, when it
#                       already exists (after a reboot herdr-app keeps the
#                       panes but runs a plain shell in them), resume each
#                       member's Claude session in its own pane
#   herdr-team launch   open herdr-app, wait for it, then run `app`; this is
#                       what the "Herdr Team" launcher entry runs
#
# Each member's session is found by its display name (claude -n): Claude
# stores it in the transcript as customTitle, and it survives /clear. A
# member whose session is still open somewhere else (e.g. the herdr TUI) is
# skipped: one Claude session can't run in two places.
# ===========================================================================

# Team members. Each key (lead perf bugs ui simplify) indexes every map below.
#   _HT_LABEL   display name: shown on the tab, passed as `claude -n`, and
#               and used to find its session (Claude stores it as customTitle)
#   _HT_MODEL   `claude --model` id per member; any model id or alias that
#               `claude --model` accepts (e.g. opus, sonnet, haiku) works
#   _HT_EFFORT  `claude --effort` level: low, medium, high, xhigh or max;
#               leave a member out to use Claude's default (the lead has none)
#   _HT_ROLE    one-line mandate appended to the worker's system prompt; a
#               member without a role (the lead) gets no extra prompt
# To add a member: add the key to all maps, then add a tab or pane for it in
# the `app` branch and to the roster loop.
typeset -gA _HT_LABEL=(
  lead     "Opus 5.5 Lead"
  perf     "Worker Haiku - Performance"
  bugs     "Worker Sonnet - Bug Fixes"
  ui       "Worker Opus - UI Polish"
  simplify "Worker Opus - Architecture"
)
typeset -gA _HT_MODEL=(
  lead claude-opus-5-5  perf claude-haiku-5-5  bugs claude-sonnet-5-5
  ui   claude-opus-5-5  simplify claude-opus-5-5
)
typeset -gA _HT_EFFORT=(perf xhigh bugs xhigh ui high simplify high)
typeset -gA _HT_ROLE=(
  perf     "Improve measurable performance bottlenecks."
  bugs     "Fix real bugs affecting normal usage; no speculative edge-case hardening or bikeshedding."
  ui       "Polish the existing UI/UX."
  simplify "Simplify architecture, remove duplication and unnecessary abstractions; prefer elegance and deletion over more machinery."
)
# Paths.
#   _HT_DIR   folder every member starts in (the shared git checkout)
#   _HT_PROJ  Claude's transcript folder for _HT_DIR (path with / → -)
_HT_DIR=$HOME/nixos-config
_HT_PROJ=$HOME/.claude/projects/${_HT_DIR//\//-}
# Team rules, appended to every worker's system prompt (after its role), so
# a fresh session gets them without being told.
_HT_RULES="Team rules: you share one git checkout ($_HT_DIR, branch main) with the other workers; expect concurrent edits and re-read a file right before editing it. Coordinate directly with other workers via \`hc send <terminal id> \"<text>\"\`; the ids arrive in a roster message after startup. Make routine decisions yourself. Message the lead only with completed work, unresolved blockers, or important decisions needing input; no chatter or progress updates. Never commit, push, or run nixos-rebuild switch: the lead does that after review. Dry-build NixOS changes before reporting them done."

# _ht_session <member> — print the id of the member's newest session in
# _HT_PROJ (transcript whose customTitle is its label), or nothing.
#   Example: _ht_session bugs   → 6d97a5dc-…
_ht_session() {
  local f=$(grep -lF "\"customTitle\":\"${_HT_LABEL[$1]}\"" $_HT_PROJ/*.jsonl(N) 2>/dev/null | xargs -r ls -t | head -1)
  [[ -n $f ]] && print -r -- ${${f:t}%.jsonl}
}

# _ht_live <session id> — true when a running claude process holds that
# session (Claude keeps ~/.claude/sessions/<pid>.json per running session).
_ht_live() {
  local f
  for f in ~/.claude/sessions/<->.json(N); do
    kill -0 ${f:t:r} 2>/dev/null && [[ $(jq -r .sessionId $f) == $1 ]] && return 0
  done
  return 1
}

# _ht_cmd <member> — set reply to the claude command line for one member:
#   claude [--resume <id>] --model <model> [--effort <level>]
#          -n <label> [--append-system-prompt "<role + team rules>"]
# --resume is added when _ht_session finds a session for that member.
_ht_cmd() {
  local k=$1 id=$(_ht_session $1)
  reply=(claude)
  [[ -n $id ]] && reply+=(--resume "$id")
  reply+=(--model "${_HT_MODEL[$k]}")
  [[ -n ${_HT_EFFORT[$k]} ]] && reply+=(--effort "${_HT_EFFORT[$k]}")
  reply+=(-n "${_HT_LABEL[$k]}")
  [[ -n ${_HT_ROLE[$k]} ]] && reply+=(--append-system-prompt \
    "You are ${_HT_LABEL[$k]}, a worker agent. Your mandate: ${_HT_ROLE[$k]} Stay strictly within this mandate. $_HT_RULES")
}

# _ht_argv <member> — the member's command as a JSON array (herdr-app --argv).
_ht_argv() { _ht_cmd $1; jq -cn '$ARGS.positional' --args -- "${reply[@]}"; }

# _ht_do <command> [args…] — run `herdr-app do <command> [args…]` and print
# its JSON reply. Succeeds only when the reply has a "terminal" field; on
# failure prints the reply to stderr and returns 1.
#   Example: _ht_do tab.new --name Workers --folder ~/nixos-config --argv '["zsh"]'
_ht_do() {
  local out
  out=$(herdr-app do "$@") && jq -e '.terminal' <<<"$out" >/dev/null || {
    print -u2 "herdr-team: '$1' failed: $out"; return 1; }
  print -r -- "$out"
}

# herdr-team app|launch — see the file header. Any other argument prints the
# usage line and returns 1.
herdr-team() {
  case $1 in
    # app, space exists: for each member find its terminal by the herdr.team
    # label (set when the space is built). A shell there gets the member's
    # claude command typed in (hc send); any other program (a running claude)
    # is left alone, so nothing is ever typed into a busy pane; a
    # session open elsewhere is skipped with a note.
    # app, no space: build it.
    #   space "nixos team"  tab named after the lead, running the lead
    #   tab "Workers"       2x2 grid: perf (top left), bugs (top right),
    #                       ui (bottom left), simplify (bottom right)
    # Each terminal gets the label herdr.team=<member>, and every member is
    # sent the terminal ids so they can message each other with `hc send`.
    app)
      local k tm id; local -A t
      if herdr-app ls 2>/dev/null | jq -e '.spaces[] | select(.name == "nixos team")' >/dev/null; then
        for tm in ${(f)"$(hc ls | jq -r ".terminals[].address")"}; do
          k=$(hc get $tm | jq -r '.labels["herdr.team"] // empty')
          [[ -n $k ]] || continue
          if [[ $(hc get $tm | jq -r .foreground.name) != (bash|zsh|sh|fish) ]]; then print "  $k\t$tm  busy (not at a shell prompt), left alone"; continue; fi
          id=$(_ht_session $k)
          if [[ -n $id ]] && _ht_live $id; then print -u2 "  $k\t$tm  session open elsewhere (/exit it there, then run again)"; continue; fi
          _ht_cmd $k
          hc send $tm "${(j: :)${(@q)reply}}" >/dev/null && print "  $k\t$tm  ${id:+resumed $id}${id:-new session}"
        done
        return
      fi
      local o
      o=$(_ht_do space.new --name "nixos team" --folder $_HT_DIR --tab "${_HT_LABEL[lead]}" --argv "$(_ht_argv lead)") || return 1
      t[lead]=$(jq -r .terminal <<<$o)
      o=$(_ht_do tab.new --name Workers --folder $_HT_DIR --argv "$(_ht_argv perf)") || return 1
      t[perf]=$(jq -r .terminal <<<$o)
      # tab.new returns no pane id, so find perf's pane by its terminal id.
      local A=$(herdr-app ls | jq -r --arg t ${t[perf]} '.. | objects | select(.terminal? == $t) | .pane' | head -1)
      # 2x2 grid, same as the TUI layout: split perf's pane right (bugs), then
      # split each column down (ui under perf, simplify under bugs).
      o=$(_ht_do pane.split --direction right --pane $A --argv "$(_ht_argv bugs)") || return 1
      t[bugs]=$(jq -r .terminal <<<$o); local B=$(jq -r .pane <<<$o)
      o=$(_ht_do pane.split --direction down --pane $A --argv "$(_ht_argv ui)") || return 1
      t[ui]=$(jq -r .terminal <<<$o)
      o=$(_ht_do pane.split --direction down --pane $B --argv "$(_ht_argv simplify)") || return 1
      t[simplify]=$(jq -r .terminal <<<$o)

      # Label each terminal for later resumes, then send every member the
      # terminal ids. `hc wait` (up to 60 s) lets each Claude finish starting
      # first; a member that misses the roster is reported on stderr.
      local roster="Team roster (herdr-app; message with \`hc send <id> \"<text>\"\`): lead=${t[lead]}, perf=${t[perf]}, bugs=${t[bugs]}, ui=${t[ui]}, simplify=${t[simplify]}. Team rules are in your system prompt. Do not reply to this message."
      for k in lead perf bugs ui simplify; do
        hc label ${t[$k]} herdr.team=$k >/dev/null
        hc wait ${t[$k]} --timeout 60 >/dev/null 2>&1
        hc send ${t[$k]} "$roster" >/dev/null && print "  $k\t${t[$k]}" || print -u2 "  $k\t${t[$k]}  (roster not sent)"
      done
      ;;
    # launch: start herdr-app detached unless its window already answers,
    # wait up to 30 s for it, then run `app`.
    launch)
      if ! herdr-app status >/dev/null 2>&1; then
        setsid -f herdr-app >/dev/null 2>&1
        local i; for i in {1..30}; do herdr-app status >/dev/null 2>&1 && break; sleep 1; done
      fi
      # Started from the launcher there is no terminal to read app's notes,
      # so members it could not resume are reported as a desktop notification.
      local out; out=$(herdr-team app 2>&1); print -r -- "$out"
      local n=${#${(M)${(f)out}:#*open elsewhere*}}
      (( n )) && notify-send -a "Herdr Team" "Herdr Team: $n not resumed" \
        "Still open in another place (e.g. the herdr TUI). /exit them there, then open Herdr Team again."
      ;;
    *) print -u2 "usage: herdr-team app|launch"; return 1 ;;
  esac
}
