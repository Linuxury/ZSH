# ===========================================================================
# conf.d/herdr/team.zsh — herdr-team: a lead + four workers Claude team
#
# Defines the herdr-team command, which lays out a team of Claude Code
# sessions in herdr-app (one lead tab, one "Workers" tab split 2x2) and can
# save/restore which Claude session each member is running. Loaded with
# every other conf.d/*/*.zsh file by zshrc; it does nothing until called.
# Needs claude, jq, herdr-app and hc on PATH.
#
#   herdr-team save   record each running member's current Claude session id
#                     (works for a team in the herdr TUI or in herdr-app)
#   herdr-team app    with herdr-app open, build the team there, resuming the
#                     saved sessions
#
# Close the old team (/exit in each member) before `app`: one Claude session
# can't run in two places. A member with no saved id (or no team.json at
# all) starts a fresh session.
# ===========================================================================

# Team members. Each key (lead perf bugs ui simplify) indexes every map below.
#   _HT_LABEL   display name: shown on the tab, passed as `claude -n`, and
#               used by `save` to recognise a running member
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
#   _HT_FILE  where `save` writes {"<member key>": "<session id>", …}
#   _HT_DIR   folder every member starts in (the shared git checkout)
_HT_FILE=$HOME/.config/herdr-app/team.json
_HT_DIR=$HOME/nixos-config
# Team rules, appended to every worker's system prompt (after its role), so
# a fresh session gets them without being told.
_HT_RULES="Team rules: you share one git checkout ($_HT_DIR, branch main) with the other workers; expect concurrent edits and re-read a file right before editing it. Coordinate directly with other workers via \`hc send <terminal id> \"<text>\"\`; the ids arrive in a roster message after startup. Make routine decisions yourself. Message the lead only with completed work, unresolved blockers, or important decisions needing input; no chatter or progress updates. Never commit, push, or run nixos-rebuild switch: the lead does that after review. Dry-build NixOS changes before reporting them done."

# _ht_argv <member> — print the claude command line for one member as a JSON
# array, the form herdr-app's --argv takes.
#   claude [--resume <saved id>] --model <model> [--effort <level>]
#          -n <label> [--append-system-prompt "<role + team rules>"]
# --resume is added only when _HT_FILE has an id for that member.
#   Example: _ht_argv bugs
#            → ["claude","--model","claude-sonnet-5-5","--effort","xhigh",…]
_ht_argv() {
  local k=$1 id
  id=$(jq -r --arg k "$k" '.[$k] // empty' "$_HT_FILE" 2>/dev/null)
  local -a a=(claude)
  [[ -n $id ]] && a+=(--resume "$id")
  a+=(--model "${_HT_MODEL[$k]}")
  [[ -n ${_HT_EFFORT[$k]} ]] && a+=(--effort "${_HT_EFFORT[$k]}")
  a+=(-n "${_HT_LABEL[$k]}")
  [[ -n ${_HT_ROLE[$k]} ]] && a+=(--append-system-prompt \
    "You are ${_HT_LABEL[$k]}, a worker agent. Your mandate: ${_HT_ROLE[$k]} Stay strictly within this mandate. $_HT_RULES")
  jq -cn '$ARGS.positional' --args -- "${a[@]}"
}

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

# herdr-team save|app — see the file header. Any other argument prints the
# usage line and returns 1.
#   Example: herdr-team save     then /exit every member, then: herdr-team app
herdr-team() {
  case $1 in
    # save: Claude Code keeps ~/.claude/sessions/<pid>.json for each running
    # session, holding its current sessionId (a new one after /clear) and its
    # -n name. For every file whose pid is still alive, match the name against
    # _HT_LABEL and write {member: sessionId} to _HT_FILE (via a .tmp file and
    # mv, so a failed write never leaves a half-written team.json).
    save)
      local f k n; local -a kv
      for f in ~/.claude/sessions/<->.json(N); do
        kill -0 ${f:t:r} 2>/dev/null || continue
        n=$(jq -r '.name // empty' $f)
        for k in ${(k)_HT_LABEL}; do
          [[ ${_HT_LABEL[$k]} == $n ]] && kv+=($k "$(jq -r .sessionId $f)")
        done
      done
      (( $#kv )) || { print -u2 "herdr-team save: no running team members found"; return 1; }
      mkdir -p ${_HT_FILE:h}
      jq -n '$ARGS.positional as $a | [range(0; $a | length; 2) | {key: $a[.], value: $a[. + 1]}] | from_entries' \
        --args -- "${kv[@]}" >| $_HT_FILE.tmp && mv $_HT_FILE.tmp $_HT_FILE || return 1
      jq -r 'to_entries[] | "  \(.key)\t\(.value)"' $_HT_FILE
      print "Saved to $_HT_FILE. To rebuild: close the team (/exit), then: herdr-team app"
      ;;
    # app: refuse if a "nixos team" space is already open, then build it.
    #   space "nixos team"  tab named after the lead, running the lead
    #   tab "Workers"       2x2 grid: perf (top left), bugs (top right),
    #                       ui (bottom left), simplify (bottom right)
    # Each terminal id is kept in t[member] for the roster message below.
    app)
      herdr-app ls 2>/dev/null | jq -e '.spaces[] | select(.name == "nixos team")' >/dev/null \
        && { print -u2 "herdr-team: a 'nixos team' space already exists in herdr-app"; return 1; }
      local o; local -A t
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

      # Send every member the terminal ids so they can message each other
      # with `hc send`. `hc wait` (up to 60 s) lets each Claude finish
      # starting first; a member that misses the roster is reported on stderr.

      local roster="Team roster (herdr-app; message with \`hc send <id> \"<text>\"\`): lead=${t[lead]}, perf=${t[perf]}, bugs=${t[bugs]}, ui=${t[ui]}, simplify=${t[simplify]}. Team rules are in your system prompt. Do not reply to this message."
      local k
      for k in lead perf bugs ui simplify; do
        hc wait ${t[$k]} --timeout 60 >/dev/null 2>&1
        hc send ${t[$k]} "$roster" >/dev/null && print "  $k\t${t[$k]}" || print -u2 "  $k\t${t[$k]}  (roster not sent)"
      done
      ;;
    *) print -u2 "usage: herdr-team save|app"; return 1 ;;
  esac
}
