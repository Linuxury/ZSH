# herdr-team — move the Lead + Workers Claude team from the herdr TUI to herdr-app.
#   herdr-team save   in the TUI: remember each agent's Claude session id
#   herdr-team app    with herdr-app open: rebuild the team there, resuming those sessions
# Quit the TUI agents between the two (/exit): one Claude session can't run twice.
# A worker with no saved id starts a fresh session.

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
    "You are ${_HT_LABEL[$k]}, a worker agent. Your mandate: ${_HT_ROLE[$k]} Stay strictly within this mandate.")
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
      [[ ${HERDR_ENV:-} == 1 ]] || { print -u2 "herdr-team save: run it inside the herdr TUI"; return 1; }
      mkdir -p ${_HT_FILE:h}
      herdr agent list | jq '[.result.agents[]
        | {key: (if .name == "opus-5-5-lead" then "lead" else .name end), value: .agent_session.value}
        | select(.key | IN("lead","perf","bugs","ui","simplify"))] | from_entries' >| $_HT_FILE || return 1
      jq -r 'to_entries[] | "  \(.key)\t\(.value)"' $_HT_FILE
      print "Saved to $_HT_FILE. Now /exit each TUI agent, open herdr-app and run: herdr-team app"
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

      local roster="Team update: you now run in herdr-app, not the herdr TUI. \`herdr agent prompt\` no longer reaches anyone; message with \`hc send <id> \"<text>\"\` instead. Ids: lead=${t[lead]}, perf=${t[perf]}, bugs=${t[bugs]}, ui=${t[ui]}, simplify=${t[simplify]}. Everything else in the earlier briefing still applies. Do not reply to this message."
      local k
      for k in lead perf bugs ui simplify; do
        hc wait ${t[$k]} --timeout 60 >/dev/null 2>&1
        hc send ${t[$k]} "$roster" >/dev/null && print "  $k\t${t[$k]}" || print -u2 "  $k\t${t[$k]}  (roster not sent)"
      done
      ;;
    *) print -u2 "usage: herdr-team save|app"; return 1 ;;
  esac
}
