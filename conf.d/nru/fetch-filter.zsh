# ---------------------------------------------------------------------------
# _nix_fetch_filter — stdin filter used by _nixos_run.
#
#   - Build noise (agenix, store paths, systemd-run chatter): dropped
#   - "these N derivations will be built" / "building …":    ⚒ progress
#   - "these N paths will be fetched" / "copying path …":    ⬇ progress
#     Repeated rounds add to the same bar instead of starting a new one;
#     the final ⬇/⚒ lines print once, before the first normal line or at the end.
#   - Unit start/stop/restart lines: counted, summarised at the end
#   - Everything from the first "error:" on: hidden — _nixos_run prints a
#     summary and saves the full log instead
#   - Everything else (activation, warnings): passed through
#
# Args: STATE_FILE (read by _nru_ticker), CACHE_DIR (stats + unit list)
# ---------------------------------------------------------------------------
_nix_fetch_filter() {
  awk -v statef="$1" -v cachedir="$2" '
  BEGIN { bw=20; ft=0; fd=0; bt=0; bd=0; kind=""; label=""; active=0; err=0
          cur="eval"   # what the ticker is drawing right now ("" = nothing)
          fetched=0; built=0; dl_mib=0
          n_stopped=0; n_restarted=0; n_reloaded=0; n_started=0; n_new=0; n_failed=0 }

  function state() {
    cur = (kind == "fetch") ? sprintf("fetch|%d|%d|%s", fd, ft, label) : sprintf("build|%d|%d|%s", bd, bt, label)
    printf "%s\n", cur > statef; close(statef)
  }
  # Pause the ticker and clear its line (it waits 0.15s so a frame in flight lands first).
  function quiet() {
    printf "" > statef; close(statef)
    system("sleep 0.15")
    printf "\r\033[K" > "/dev/tty"; fflush("/dev/tty")
  }
  # Stop the ticker for good (bars done, error, or activation started).
  function stop() { if (cur == "") return; quiet(); cur = "" }
  # Print a normal line without colliding with the ticker, then let it resume
  # (e.g. a warning during "Evaluating…").
  function say(line) {
    if (cur != "") quiet()
    print line; fflush()
    if (cur != "") { printf "%s\n", cur > statef; close(statef) }
  }
  function bar(d, t,   f, s, i) {
    f = int(d * bw / (t > 0 ? t : 1)); s = ""
    for (i = 0; i < f; i++) s = s "■"
    for (; i < bw; i++) s = s "□"
    return s
  }
  function size(m) { return m >= 1024 ? sprintf("%.1f GiB", m / 1024) : sprintf("%.0f MiB", m) }
  # Print the final ⬇ / ⚒ lines once; later rounds (rare) start fresh bars.
  function finals() {
    stop()
    if (!active) return
    if (ft) printf "  ⬇  %-12s  [%s]  %3d%%  %s\n", fd "/" ft, bar(fd, ft), int(fd * 100 / ft), size(dl_mib) > "/dev/tty"
    if (bt) {
      if (err) printf "  ⚒  %-12s  [%s]  %3d%%  stopped\n", bd "/" bt, bar(bd, bt), int(bd * 100 / bt) > "/dev/tty"
      else     printf "  ⚒  %-12s  [%s]  100%%  %s\n", bt "/" bt, bar(1, 1), (bd < bt ? "cached" : "built") > "/dev/tty"
    }
    fflush("/dev/tty")
    active = 0; ft = 0; fd = 0; bt = 0; bd = 0
  }
  # "these 98 derivations …" → 98; singular "this path …" → 1 (its first number is the size)
  function count(l) { return (l ~ /^these [0-9]+/ && match(l, /[0-9]+/)) ? substr(l, RSTART, RLENGTH) + 0 : 1 }
  function add_unit(action, unit) {
    if (action == "stopped")   { if (!stopped_seen[unit])   { stopped_seen[unit]=1;   stopped_ord[++n_stopped]=unit   } }
    if (action == "restarted") { if (!restarted_seen[unit]) { restarted_seen[unit]=1; restarted_ord[++n_restarted]=unit } }
    if (action == "reloaded")  { if (!reloaded_seen[unit])  { reloaded_seen[unit]=1;  reloaded_ord[++n_reloaded]=unit  } }
    if (action == "started")   { if (!started_seen[unit])   { started_seen[unit]=1;   started_ord[++n_started]=unit   } }
    if (action == "new")       { if (!new_seen[unit])       { new_seen[unit]=1;       new_ord[++n_new]=unit           } }
    if (action == "failed")    { if (!failed_seen[unit])    { failed_seen[unit]=1;    failed_ord[++n_failed]=unit     } }
  }
  function list_group(label, arr, n,   i) {
    if (n == 0) return
    printf "%s\n", label > unitsf
    for (i = 1; i <= n; i++) printf "  %s\n", arr[i] > unitsf
  }

  { l = tolower($0) }

  # After the first error, nothing more goes to the screen.
  err                                                   { next }
  /^[[:space:]]*error:/                                 { finals(); err = 1; next }

  /^\[agenix\]/ || /^decrypting /                      { next }
  # Eval-time warnings already get parsed from the log by nixos-log-rebuild
  # and shown in the "Flagged" block after the build.
  /^evaluation warning:/                                { next }
  /^warning: Git tree .* is dirty/                      { next }
  /^warning: ignoring substitute for /                  { next }
  /^warning: file .* does not exist in binary cache /   { next }
  /^Done\. The new configuration is \/nix\/store\//     { next }
  /^building the system configuration/                  { next }
  /^[[:space:]]+\/nix\/store\//                         { next }
  /^Checking switch inhibitors/                         { next }
  /^activating the configuration/                       { next }
  /^setting up \/etc/                                   { next }
  /^reloading user units for /                          { next }
  /^Skipping "\//                                       { next }
  /^unpacking \47.*\47 into the Git cache/               { next }
  /^NOT restarting the following (changed|user) units:/  { next }
  # systemd-run chatter from switch-to-configuration — the wall-clock time is
  # pulled from the raw log by _nixos_run and shown on the success line.
  /^Start(ing|ed) \[systemd-run\] /                        { next }
  /^(switching|finished switching) to system configuration / { next }
  /^nixos-rebuild-switch-to-configuration\.service: (Deactivated|Consumed) / { next }

  # nix prints the singular form ("This derivation will be built:") for one item
  l ~ /^(these [0-9]+ derivations|this derivation) will be built/ {
    bt += count(l); kind = "build"; label = "starting…"; active = 1; state(); next
  }
  # -L build-log lines ("noctalia> [312/840] Compiling …"): never shown, but
  # they name the package that is ACTUALLY busy — "building" lines only say
  # what started last, and nix never prints when a build finishes.
  bt && /^[A-Za-z0-9][A-Za-z0-9._+-]*> / {
    pkg = substr($0, 1, index($0, ">") - 1); step = ""
    if (match($0, /\[[0-9]+\/[0-9]+\]/)) step = " " substr($0, RSTART, RLENGTH)
    if (pkg step != label) { label = substr(pkg, 1, 30 - length(step)) step; kind = "build"; state() }
    next
  }
  /^building .*\/nix\/store\// {
    if (!bt) next
    bd++; built++
    path = $0
    sub(/^building \47?\/nix\/store\/[a-z0-9]+-/, "", path)
    sub(/\.drv.*$/, "", path)
    label = substr(path, 1, 30); kind = "build"; state(); next
  }
  l ~ /^(these [0-9]+ paths|this path) will be fetched/ {
    ft += count(l)
    if (match(l, /[0-9.]+ [kmg]ib download/)) {
      split(substr(l, RSTART, RLENGTH), a, " ")
      dl_mib += (a[2] == "kib" ? a[1] / 1024 : a[2] == "gib" ? a[1] * 1024 : a[1])
    }
    kind = "fetch"; label = "starting…"; active = 1; state(); next
  }
  /^copying path / {
    if (!ft) next
    fd++; fetched++
    path = $0
    sub(/^copying path \47\/nix\/store\/[a-z0-9]+-/, "", path)
    sub(/\47.*$/, "", path)
    label = substr(path, 1, 30); kind = "fetch"; state(); next
  }

  # Units that failed to start during the switch
  /^warning: the following units failed: / {
    rest = $0; sub(/^.*units failed: /, "", rest)
    n_u = split(rest, us, ", ")
    for (i = 1; i <= n_u; i++) add_unit("failed", us[i])
    next
  }
  # Single-unit action lines (e.g. "restarting sysinit-reactivation.target")
  /^(stopping|starting|restarting|reloading) / && !/the following/ {
    if      (/^stopping/)   add_unit("stopped",   $2)
    else if (/^starting/)   add_unit("started",   $2)
    else if (/^restarting/) add_unit("restarted", $2)
    else if (/^reloading/)  add_unit("reloaded",  $2)
    next
  }
  # Multi-unit action lines
  /^(stopping|starting|restarting|reloading) the following .*units?: / ||
  /^the following new units were started: / {
    finals()
    n_u = split(substr($0, index($0, ": ") + 2), us, ", ")
    if      (/^stopping/)          for (i=1; i<=n_u; i++) add_unit("stopped",   us[i])
    else if (/^starting/)          for (i=1; i<=n_u; i++) add_unit("started",   us[i])
    else if (/^restarting/)        for (i=1; i<=n_u; i++) add_unit("restarted", us[i])
    else if (/^reloading/)         for (i=1; i<=n_u; i++) add_unit("reloaded",  us[i])
    else if (/^the following new/) for (i=1; i<=n_u; i++) add_unit("new",       us[i])
    next
  }

  { if (active) finals(); say($0) }

  END {
    finals()
    printf "" > statef; close(statef)
    printf "fetched=%d\ndl_mib=%.1f\nbuilt=%d\nfailed_units=%d\n", fetched, dl_mib, built, n_failed > (cachedir "/last-run.stats")

    total = n_stopped + n_restarted + n_reloaded + n_started + n_new + n_failed
    if (total == 0) exit
    unitsf = cachedir "/last-units.txt"
    printf "" > unitsf
    list_group("Failed", failed_ord, n_failed)
    list_group("Stopped", stopped_ord, n_stopped)
    list_group("Restarted", restarted_ord, n_restarted)
    list_group("Reloaded", reloaded_ord, n_reloaded)
    list_group("Started", started_ord, n_started)
    list_group("New", new_ord, n_new)

    line = ""; for (j = 0; j < 58; j++) line = line "─"
    printf "\n─── Units %s\n", substr(line, 1, 48)
    s = ""
    if (n_stopped)   s = s n_stopped " stopped · "
    if (n_restarted) s = s n_restarted " restarted · "
    if (n_reloaded)  s = s n_reloaded " reloaded · "
    if (n_started)   s = s n_started " started · "
    if (n_new)       s = s n_new " new · "
    printf "  %s%d failed\n", s, n_failed
    for (i = 1; i <= n_failed; i++) printf "  ✗ %s failed\n", failed_ord[i]
    printf "%s\n", line
  }
  '
}

