# herdr-team — run the Lead + Workers Claude team in herdr-app.
#   herdr-team save   (TUI or app) remember each running member's current Claude session id
#   herdr-team app    with herdr-app open: build the team there, resuming saved sessions
# Close the old team before `app` (/exit): one Claude session can't run twice.
# No saved id (or no team.json) = a fresh session for that member.

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
_HT_FILE=$HOME/.config/herdr-app/team.json
_HT_DIR=$HOME/nixos-config
# Team rules, in every worker's system prompt so fresh sessions get them too.
_HT_RULES="Team rules: you share one git checkout ($_HT_DIR, branch main) with the other workers; expect concurrent edits and re-read a file right before editing it. Coordinate directly with other workers via \`hc send <terminal id> \"<text>\"\`; the ids arrive in a roster message after startup. Make routine decisions yourself. Message the lead only with completed work, unresolved blockers, or important decisions needing input; no chatter or progress updates. Never commit, push, or run nixos-rebuild switch: the lead does that after review. Dry-build NixOS changes before reporting them done."

# JSON argv for one member: claude [--resume id] --model … [--effort …] -n … [--append-system-prompt …]
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

# Run one herdr-app command; print its JSON, or fail loudly.
_ht_do() {
  local out
  out=$(herdr-app do "$@") && jq -e '.terminal' <<<"$out" >/dev/null || {
    print -u2 "herdr-team: '$1' failed: $out"; return 1; }
  print -r -- "$out"
}

herdr-team() {
  case $1 in
    save)
      # Claude Code keeps ~/.claude/sessions/<pid>.json per running session, with its
      # current sessionId (changes on /clear) and -n name. Match members by that name.
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
    app)
      herdr-app ls 2>/dev/null | jq -e '.spaces[] | select(.name == "nixos team")' >/dev/null \
        && { print -u2 "herdr-team: a 'nixos team' space already exists in herdr-app"; return 1; }
      local o; local -A t
      o=$(_ht_do space.new --name "nixos team" --folder $_HT_DIR --tab "${_HT_LABEL[lead]}" --argv "$(_ht_argv lead)") || return 1
      t[lead]=$(jq -r .terminal <<<$o)
      o=$(_ht_do tab.new --name Workers --folder $_HT_DIR --argv "$(_ht_argv perf)") || return 1
      t[perf]=$(jq -r .terminal <<<$o)
      # tab.new returns no pane id; look it up by terminal.
      local A=$(herdr-app ls | jq -r --arg t ${t[perf]} '.. | objects | select(.terminal? == $t) | .pane' | head -1)
      # Same 2x2 as the TUI: split right, then each column down.
      o=$(_ht_do pane.split --direction right --pane $A --argv "$(_ht_argv bugs)") || return 1
      t[bugs]=$(jq -r .terminal <<<$o); local B=$(jq -r .pane <<<$o)
      o=$(_ht_do pane.split --direction down --pane $A --argv "$(_ht_argv ui)") || return 1
      t[ui]=$(jq -r .terminal <<<$o)
      o=$(_ht_do pane.split --direction down --pane $B --argv "$(_ht_argv simplify)") || return 1
      t[simplify]=$(jq -r .terminal <<<$o)

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
