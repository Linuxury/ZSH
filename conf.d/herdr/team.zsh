# herdr-team — a "desktop team" of Claude sessions in herdr-app: one Opus lead
# decides, short-lived workers (perf, bugs, ui, simplify) do the reading and
# writing. Needs claude, jq, herdr-app, hc, notify-send.
#
#   herdr-team launch                       open herdr-app if needed, then start
#   herdr-team space <name> [folder]        a plain space: Main tab + Workers tab, 2x2 shells
#   herdr-team launch full                  launch + one idle worker of each type (2x2)
#   herdr-team start                        build the space + lead (fresh each time)
#   herdr-team worker <type> --files a,b "<brief>"    (lead) start a worker
#   herdr-team claim <file>                 (worker) take a file, or "held by <w>"
#   herdr-team report "<text>"              (worker) report once, release claims
#   herdr-team inbox | wait | workers       (lead) read reports / block / list
#   herdr-team stop <worker>                (lead) quit a worker + close its pane, release claims
#
# Who is who comes from the herdr.team label on a terminal (hc label), read via
# $HC_TERMINAL_ID, which herdr-core sets in every hc terminal. Nothing is
# resumed: each start is fresh, continuity comes from the vault notes.
# State: ~/.cache/herdr-team/ (claims.tsv, workers.tsv, inbox/, inbox/read/).

typeset -gA _HT_MODEL=(lead claude-opus-5-5 perf claude-haiku-5-5 bugs claude-sonnet-5-5 ui claude-opus-5-5 simplify claude-opus-5-5)
typeset -gA _HT_EFFORT=(perf xhigh bugs xhigh ui high simplify high)
typeset -gA _HT_ROLE=(
  perf     "Mandate: measurable performance work (startup, evaluation, closure size) and simple, well-defined edits. Measure before and after."
  bugs     "Mandate: real bugs that bite in normal use. Reproduce first; skip theoretical ones."
  ui       "Mandate: polish UI/UX (layout, spacing, theming, consistency)."
  simplify "Mandate: architecture, duplication, dead flexibility. Delete before adding."
)
_HT_DIR=$HOME/nixos-config
_HT_STATE=$HOME/.cache/herdr-team
_HT_SPACE="desktop team"
_HT_FILE=${(%):-%x}   # this file, for the wrapper below
_HT_BIN=$_HT_STATE/herdr-team   # claude's Bash tool is bash: it can't see this zsh function
_HT_CAP=4    # most live workers at once

_HT_LEAD_PROMPT='You are the Desktop Lead of a herdr team. You decide; workers read and write. Run `herdr-team` for everything.
- Start a worker only when a task needs its mandate: `herdr-team worker <perf|bugs|ui|simplify> --files a,b "<brief>"`. For simple work that splits by file, prefer several perf workers with disjoint --files. Workers never start workers; every worker reports to you.
- Choose per task: `herdr-team wait` (block until all live workers reported) or rolling (`herdr-team inbox` on each "report ready: <worker>" ping).
- Schedule the findings from the reports yourself. Stop a worker you will not reuse: `herdr-team stop <worker>`. After `herdr-team full` the four workers are already idle: list them with `herdr-team workers`, assign work with `hc send <terminal> "<task, files>"` (they claim the files themselves). Keep your cache warm while workers are out.
- Commit, push and nixos-rebuild switch only with the user'"'"'s explicit approval. Dry-build first. No Co-Authored-By trailers.'

_HT_WORKER_PROMPT='You are a herdr team worker. Stay inside your mandate and your claimed files; run `herdr-team claim <file>` before touching any other file (it refuses with "held by <worker>"). Never fix or delegate out-of-mandate findings: list them in your report with file:line and the suggested worker type. Report once per assignment with `herdr-team report "<text>"`, the text ending `Status: DONE | UNSURE | BLOCKED`. Never start workers, commit, push or switch.'

# _ht_prompt <text> — the prompt with `herdr-team ` calls pointing at the wrapper.
_ht_prompt() { print -r -- "${1//\`herdr-team /\`$_HT_BIN }"; }

# _ht_label <terminal> — its herdr.team label (empty when none).
_ht_label() { hc get $1 | jq -r '.labels["herdr.team"] // empty'; }

# _ht_term <label> — terminal id carrying herdr.team=<label>, or nothing.
_ht_term() {
  local tm
  for tm in ${(f)"$(hc ls | jq -r '.terminals[].address')"}; do
    [[ $(_ht_label $tm) == $1 ]] && { print $tm; return; }
  done
}

# _ht_me — the caller's team name (lead, perf-1, …), or nothing.
_ht_me() { [[ -n $HC_TERMINAL_ID ]] && _ht_label $HC_TERMINAL_ID; }

# _ht_do <command> [args…] — `herdr-app do …`; prints the JSON reply, and only
# succeeds when it has a "terminal" field (else the reply goes to stderr).
_ht_do() {
  local out
  out=$(herdr-app do "$@") && jq -e '.terminal' <<<"$out" >/dev/null || {
    print -u2 "herdr-team: '$1' failed: $out"; return 1; }
  print -r -- "$out"
}

# _ht_pane <terminal> — its pane id (tab.new returns none).
_ht_pane() { herdr-app ls | jq -r --arg t $1 '.. | objects | select(.terminal? == $t) | .pane' | head -1; }

# _ht_argv <model> <effort> <name> <prompt> [first message] — claude command as JSON.
_ht_argv() {
  local -a c=(claude --model $1 -n $3 --append-system-prompt $4)
  [[ -n $2 ]] && c+=(--effort $2)
  [[ -n $5 ]] && c+=($5)
  jq -cn '$ARGS.positional' --args -- "${c[@]}"
}

# _ht_release <worker> — drop its claims.
_ht_release() { [[ -f $_HT_STATE/claims.tsv ]] && sed -i "/\t$1\$/d" $_HT_STATE/claims.tsv; return 0; }

# _ht_lead_only / _ht_worker_only — refuse unless the caller has that role.
_ht_lead_only()   { [[ $(_ht_me) == lead ]] || { print -u2 "herdr-team: lead only"; return 1; } }
_ht_worker_only() { local me=$(_ht_me); [[ -n $me && $me != lead ]] || { print -u2 "herdr-team: workers only"; return 1; } }

# _ht_relpath <file> — repo-relative path, so claims compare equal.
_ht_relpath() { realpath -m --relative-to=$_HT_DIR -- ${1:A} }

# _ht_claim <worker> <relpath> — grant (0) or refuse (1, "held by <w>"), under a lock.
_ht_claim() {
  mkdir -p $_HT_STATE; touch $_HT_STATE/claims.tsv
  (
    flock 9
    local h=$(awk -F'\t' -v f=$2 '$1 == f {print $2; exit}' $_HT_STATE/claims.tsv)
    if [[ -n $h && $h != $1 ]]; then print -u2 "$2: held by $h"; exit 1; fi
    [[ -n $h ]] || print -r -- "$2"$'\t'"$1" >> $_HT_STATE/claims.tsv
  ) 9>$_HT_STATE/.lock
}

# _ht_live — names of workers whose terminal is still alive.
_ht_live() {
  local n t; [[ -f $_HT_STATE/workers.tsv ]] || return 0
  hc ls >$_HT_STATE/.ls
  while IFS=$'\t' read -r n t _; do
    jq -e --arg t $t '.terminals[] | select(.address == $t and .state == "live")' $_HT_STATE/.ls >/dev/null && print $n
  done < $_HT_STATE/workers.tsv
}

_ht_notify() { notify-send -a "Herdr Team" "$@" 2>/dev/null; }

herdr-team() {
  local cmd=$1; shift
  case $cmd in
    launch)
      if ! herdr-app status >/dev/null 2>&1; then
        setsid -f herdr-app >/dev/null 2>&1
        local i; for i in {1..30}; do herdr-app status >/dev/null 2>&1 && break; sleep 1; done
      fi
      # Started from the menu there is no terminal: report failure as a notification.
      if ! { herdr-team start && { [[ $1 != full ]] || herdr-team full; }; }; then
        _ht_notify "Herdr Team: failed to start" "Run herdr-team start in a terminal to see why."; return 1
      fi
      ;;

    # space: the team's shape without Claude: tab "Main" plus tab "Workers"
    # with four plain shells in the same 2x2 grid. herdr-app has no
    # new-space hook, so run this instead of clicking "new space".
    space)
      [[ -n $1 ]] || { print -u2 "usage: herdr-team space <name> [folder]"; return 1; }
      local d=${2:-$PWD} o a b
      o=$(_ht_do space.new --name $1 --folder $d --tab Main --argv '["zsh"]') || return 1
      o=$(_ht_do tab.new --name Workers --folder $d --argv '["zsh"]') || return 1
      a=$(_ht_pane $(jq -r .terminal <<<$o))
      o=$(_ht_do pane.split --direction right --pane $a --argv '["zsh"]') || return 1
      b=$(jq -r .pane <<<$o)
      _ht_do pane.split --direction down --pane $a --argv '["zsh"]' >/dev/null || return 1
      _ht_do pane.split --direction down --pane $b --argv '["zsh"]' >/dev/null || return 1
      ;;

    # full: the lead (from start) plus one idle worker of each type in the 2x2.
    # Skipped when workers are already live. Idle = the brief says wait.
    full)
      [[ -n $(_ht_live) ]] && return 0
      local lt=$(_ht_term lead) t
      [[ -n $lt ]] || { print -u2 "herdr-team: no lead, run start first"; return 1; }
      for t in perf bugs ui simplify; do
        HC_TERMINAL_ID=$lt herdr-team worker $t "Idle: wait for the lead to message you an assignment. Do nothing until then, and do not reply to this message." || return 1
        sleep 2
      done
      ;;

    # start: a running lead means do nothing; otherwise close the old space,
    # clear the state, and create the space with a "Lead" tab running the lead.
    start)
      local lt=$(_ht_term lead)
      if [[ -n $lt && $(hc get $lt | jq -r .foreground.name) == (claude|.claude-wrapped) ]] \
         && herdr-app ls | jq -e --arg n $_HT_SPACE '.spaces[] | select(.name == $n)' >/dev/null; then
        _ht_notify "Herdr Team already running" "The lead is live in space \"$_HT_SPACE\"."
        return 0
      fi
      local sid=$(herdr-app ls | jq -r --arg n $_HT_SPACE '.spaces[] | select(.name == $n) | .id')
      [[ -n $sid ]] && herdr-app do space.close --id $sid --confirmed true >/dev/null
      rm -rf $_HT_STATE; mkdir -p $_HT_STATE/inbox/read
      print "#!/usr/bin/env zsh\nsource $_HT_FILE && herdr-team \"\$@\"" > $_HT_BIN; chmod +x $_HT_BIN
      : > $_HT_STATE/workers.tsv
      local o; o=$(_ht_do space.new --name $_HT_SPACE --folder $_HT_DIR --tab Lead \
        --argv "$(_ht_argv ${_HT_MODEL[lead]} '' "Desktop Lead" "$(_ht_prompt $_HT_LEAD_PROMPT)")") || return 1
      hc label $(jq -r .terminal <<<$o) herdr.team=lead >/dev/null
      print "lead\t$(jq -r .terminal <<<$o)"
      ;;

    # worker: cap + claims checked first; first worker opens tab "Workers", the
    # next ones fill a 2x2 grid (slots: 1 top-left, 2 right of 1, 3 under 1,
    # 4 under 2). ponytail: if a slot's anchor pane was stopped, splits any live pane.
    worker)
      _ht_lead_only || return 1
      local type=$1 files brief; shift
      [[ -n ${_HT_ROLE[$type]} ]] || { print -u2 "herdr-team: type is ${(kj:|:)_HT_ROLE}"; return 1; }
      [[ $1 == --files ]] && { files=$2; shift 2; }
      brief=$1
      [[ -n $brief ]] || { print -u2 'usage: herdr-team worker <type> [--files a,b] "<brief>"'; return 1; }
      local -a live=(${(f)"$(_ht_live)"})
      (( ${#live} >= _HT_CAP )) && { print -u2 "herdr-team: $_HT_CAP workers already live"; return 1; }
      local n=$(( $(cat $_HT_STATE/n-$type 2>/dev/null || print 0) + 1 )) name f
      name=$type-$n
      local -a rel=(); for f in ${(s:,:)files}; do rel+=($(_ht_relpath $f)); done
      for f in $rel; do _ht_claim $name $f || { _ht_release $name; return 1; }; done
      print $n > $_HT_STATE/n-$type

      local slot s pane dir anchor o
      local -A used; local w
      while IFS=$'\t' read -r w _ _ _ s; do [[ " $live " == *" $w "* ]] && used[$s]=1; done < $_HT_STATE/workers.tsv 2>/dev/null
      for slot in 1 2 3 4; do [[ -z ${used[$slot]} ]] && break; done
      local argv; argv=$(_ht_argv ${_HT_MODEL[$type]} ${_HT_EFFORT[$type]} $name "$(_ht_prompt $_HT_WORKER_PROMPT) ${_HT_ROLE[$type]} Your name: $name. Claimed files: ${${(j:, :)rel}:-none yet}." $brief)
      if (( ${#live} == 0 )); then
        o=$(_ht_do tab.new --name Workers --folder $_HT_DIR --argv $argv) || { _ht_release $name; return 1; }
      else
        local -A from=(2 1 3 1 4 2)
        anchor=$(awk -F'\t' -v s=${from[$slot]} '$5 == s {print $4}' $_HT_STATE/workers.tsv | head -1)
        dir=right; [[ $slot == (3|4) ]] && dir=down
        [[ -n $anchor ]] || { anchor=$(awk -F'\t' 'END {print $4}' $_HT_STATE/workers.tsv); dir=right; }
        o=$(_ht_do pane.split --direction $dir --pane $anchor --argv $argv) || { _ht_release $name; return 1; }
      fi
      local tm=$(jq -r .terminal <<<$o)
      pane=$(jq -r '.pane // empty' <<<$o); [[ -n $pane ]] || pane=$(_ht_pane $tm)
      hc label $tm herdr.team=$name >/dev/null
      print -r -- "$name"$'\t'"$tm"$'\t'"${_HT_MODEL[$type]}"$'\t'"$pane"$'\t'"$slot" >> $_HT_STATE/workers.tsv
      print "$name\t$tm"
      ;;

    claim)
      _ht_worker_only || return 1
      [[ -n $1 ]] || { print -u2 "usage: herdr-team claim <file>"; return 1; }
      _ht_claim $(_ht_me) $(_ht_relpath $1) && print "granted $(_ht_relpath $1)"
      ;;

    report)
      _ht_worker_only || return 1
      local me=$(_ht_me) lt=$(_ht_term lead)
      [[ -n $1 ]] || { print -u2 'usage: herdr-team report "<text>"'; return 1; }
      mkdir -p $_HT_STATE/inbox
      print -r -- "$1" > $_HT_STATE/inbox/$(date +%s%3N)-$me.md
      _ht_release $me
      [[ -n $lt ]] && hc send $lt "report ready: $me" >/dev/null
      ;;

    # inbox: unread reports oldest first (names start with epoch-ms), then
    # moved to inbox/read/.
    inbox)
      _ht_lead_only || return 1
      local r; for r in $_HT_STATE/inbox/*.md(N); do
        print "=== ${${r:t:r}#*-} ($(date -d @$(( ${${r:t}%%-*} / 1000 )) +%T))"; cat $r; print
        mv $r $_HT_STATE/inbox/read/
      done
      ;;

    # wait: poll until every live worker has a report (unread or read), then
    # print the unread ones. A worker whose terminal died counts as finished.
    wait)
      _ht_lead_only || return 1
      local -a pending; local w
      while :; do
        pending=(); for w in ${(f)"$(_ht_live)"}; do
          [[ -n $(print $_HT_STATE/inbox/*-$w.md(N) $_HT_STATE/inbox/read/*-$w.md(N)) ]] || pending+=($w)
        done
        (( ${#pending} )) || break
        sleep 3
      done
      herdr-team inbox
      ;;

    workers)
      _ht_lead_only || return 1
      local -a live=(${(f)"$(_ht_live)"}); local n t m p s
      while IFS=$'\t' read -r n t m p s; do
        [[ " $live " == *" $n "* ]] && print "$n\t$t\t$m\t$(awk -F'\t' -v w=$n '$2 == w {printf "%s ", $1}' $_HT_STATE/claims.tsv)"
      done < $_HT_STATE/workers.tsv 2>/dev/null
      ;;

    # stop: a pasted "/exit" is just text to claude, so type it with hc keys,
    # then close the pane (it would otherwise fall back to a shell).
    stop)
      _ht_lead_only || return 1
      local row=$(awk -F'\t' -v w=$1 '$1 == w {print $2 "\t" $4}' $_HT_STATE/workers.tsv 2>/dev/null)
      [[ -n $row ]] || { print -u2 "herdr-team: no worker $1"; return 1; }
      hc keys ${row%%$'\t'*} / e x i t enter >/dev/null
      hc wait ${row%%$'\t'*} --timeout 10 >/dev/null 2>&1
      herdr-app do pane.close --pane ${row#*$'\t'} >/dev/null
      _ht_release $1
      sed -i "/^$1\t/d" $_HT_STATE/workers.tsv
      ;;

    *) print -u2 "usage: herdr-team launch|start|full|space|worker|claim|report|inbox|wait|workers|stop"; return 1 ;;
  esac
}
