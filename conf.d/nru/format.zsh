# ===========================================================================
# conf.d/nru/format.zsh — package-change table for nru
#
# Defines _fmt_nvd, which turns `nvd diff` output into the "Packages" table
# nru prints after a successful rebuild (conf.d/nru/run.zsh calls it and
# also saves the result to ~/.cache/nru/last-packages.txt). Loaded with every
# other conf.d/*/*.zsh file by zshrc; nru skips the table when nvd is not
# installed, so removing nvd turns it off.
# ===========================================================================

# ---------------------------------------------------------------------------
# _fmt_nvd — format `nvd diff` output as an aligned package-changes table.
#
#   Input   nvd diff text on stdin; no arguments or flags.
#   Output  on stdout: header line, Package / From / To table, store-path and
#           disk-usage footer, closing divider. Nothing at all when there are
#           no package rows and nothing was rebuilt.
#   Example nvd diff /run/current-system ./result | _fmt_nvd
#
# Reads every line into arrays first and prints in a second pass, so the
# column widths fit the longest name and version before the first row prints.
# Accepts both nvd layouts: section headings ("Added packages:",
# "Removed packages:", "Version changes:") and per-line markers ([A.], [R.],
# [U*], [D.], [C.], …). nvd's marker letters: A added, R removed, U upgrade,
# D downgrade, C changed; second character: * selected (in
# environment.systemPackages), . dependency, + newly selected, - newly
# unselected.
# ---------------------------------------------------------------------------
_fmt_nvd() {
  local section="" line
  # Every loop variable is declared once, here. Re-running `local name` on a
  # variable that already exists in this function prints "name=value" to
  # stdout, which would end up inside the table.
  local pkg ver name old_v new_v rest old_vset new_vset
  local -a names=() old_vers=() new_vers=() actions=()
  local closure_old="" closure_new="" closure_added="" closure_removed="" closure_net="" closure_disk=""

  # Pass 1: parse. IFS= and -r keep leading spaces and backslashes intact.
  # Skips nvd's "<<< old" / ">>> new" path lines and blank lines.
  while IFS= read -r line; do
    [[ "$line" == '<<<'* || "$line" == '>>>'* ]] && continue
    [[ -z "${line// }" ]] && continue

    # Section headings (long layout): set which kind of row follows.
    if [[ "$line" == 'Added packages:'   ]]; then section="added";   continue; fi
    if [[ "$line" == 'Removed packages:' ]]; then section="removed"; continue; fi
    if [[ "$line" == 'Version changes:'* ]]; then section="version"; continue; fi

    # "Closure size: OLD -> NEW (A paths added, R paths removed, delta ±N,
    # disk usage SIZE)." — pulls each number out with sed -E for the footer.
    #   closure_old / closure_new          store paths before and after
    #   closure_added / closure_removed    paths added and removed
    #   closure_net                        net change in path count
    #   closure_disk                       disk usage change; nvd leaves the
    #                                      ", disk usage" part out when it
    #                                      can't measure it
    if [[ "$line" == 'Closure size:'* ]]; then
      closure_old=$(    printf '%s' "$line" | sed -E 's/Closure size: ([0-9]+).*/\1/')
      closure_new=$(    printf '%s' "$line" | sed -E 's/[^0-9]*[0-9]+ -> ([0-9]+).*/\1/')
      closure_added=$(  printf '%s' "$line" | sed -E 's/.*\(([0-9]+) paths added.*/\1/')
      closure_removed=$(printf '%s' "$line" | sed -E 's/.*, ([0-9]+) paths removed.*/\1/')
      closure_net=$(    printf '%s' "$line" | sed -E 's/.*delta ([+-]?[0-9]+).*/\1/')
      closure_disk=$(   printf '%s' "$line" | sed -E 's/.*disk usage ([^)]+)\).*/\1/')
      continue
    fi

    # Per-line marker (short layout): the first letter picks the row kind.
    #   A → added    R → removed    U / D / C → version change
    case "$line" in
      '[A.'*|'[A*'*|'[A+'*|'[A-'*) section="added"   ;;
      '[R.'*|'[R*'*|'[R+'*|'[R-'*) section="removed" ;;
      '[C.'*|'[C*'*|'[C+'*|'[C-'*|'[D.'*|'[D*'*|'[D+'*|'[D-'*|'[U.'*|'[U*'*|'[U+'*|'[U-'*) section="version" ;;
    esac

    # Turn the line into one table row: names[i], old_vers[i], new_vers[i],
    # actions[i] (added | removed | updated) all share the same index i.
    case "$section" in
      # Added / removed row: "[A.]  #12  name  version".
      #   strips the marker, the "#NN" counter and any store-hash prefix
      #   drops Home Manager and activation plumbing (source, home-manager-*,
      #   hm_*, activation-script, unit-*): rebuilt on every switch, not news
      #   keeps the first version only (", …" lists extra outputs)
      #   the version shows under To for added rows, under From for removed
      added|removed)
        pkg=$(printf '%s' "$line" | sed -E 's/^\[[A-Z].\]  #[0-9]+  //; s/^[a-z0-9]{32,}-//')
        [[ -z "$pkg" ]] && continue
        ver="${pkg##*  }"
        pkg="${pkg%%  *}"
        [[ "$pkg" == "source" || "$pkg" == "home-manager-"* || "$pkg" == "hm_"* || "$pkg" == "activation-script" || "$pkg" == "unit-"* ]] && continue
        ver=$(printf '%s' "$ver" | sed 's/, .*//')
        [[ "$ver" == "<none>" ]] && ver=$section   # unversioned (scripts): say added/removed
        names+=("$pkg")
        actions+=("$section")
        if [[ "$section" == "added" ]]; then
          old_vers+=("-"); new_vers+=("$ver")
        else
          old_vers+=("$ver"); new_vers+=("-")
        fi
        ;;
      # Version row: "[U.]  #3  name  1.2 -> 1.3". Strips the marker and the
      # "#NN" counter, splits at " -> " into old_v and new_v, and skips any
      # line without an arrow.
      version)
        pkg=$(printf '%s' "$line" | sed -E 's/^\[[A-Z][.*+-]\]  //')
        [[ -z "$pkg" ]] && continue
        pkg=$(printf '%s' "$pkg" | sed -E 's/^#[0-9]+  +//')
        [[ -z "$pkg" ]] && continue
        [[ "$pkg" != *' -> '* ]] && continue
        name="${pkg%% *}"
        rest="${pkg#"$name"}"; rest="${rest#"${rest%%[! ]*}"}"
        old_v="${rest%% -> *}"; new_v="${rest##* -> }"
        # Keep only the first version: nvd lists extra outputs after a comma,
        # e.g. "2.63.1, 2.63.1-man".
        old_v=$(printf '%s' "$old_v" | sed 's/, .*//')
        new_v=$(printf '%s' "$new_v" | sed 's/, .*//')
        # " xN" is how many copies of that version are in the closure. If the
        # versions match once the counts are removed (e.g. "1.0 x3 -> 1.0 x2"),
        # only the count changed: skip the row. Otherwise drop the count.
        old_vset=$(printf '%s' "$old_v" | sed -E 's/ x[0-9]+//g')
        new_vset=$(printf '%s' "$new_v" | sed -E 's/ x[0-9]+//g')
        [[ "$old_vset" == "$new_vset" ]] && continue
        old_v=$(printf '%s' "$old_v" | sed -E 's/ x[0-9]+//')
        new_v=$(printf '%s' "$new_v" | sed -E 's/ x[0-9]+//')
        names+=("$name"); old_vers+=("$old_v"); new_vers+=("$new_v"); actions+=("updated")
        ;;
    esac
  done

  local n_total=${#names[@]}
  # No rows. If store paths were still added (packages rebuilt at the same
  # version, e.g. flake inputs built from git), print a one-line note padded
  # with ─ to the 58-column width; otherwise print nothing.
  #   ${(l:n::─:)}  zsh left-pad flag: an empty value padded to n "─" chars
  if (( n_total == 0 )); then
    (( ${closure_added:-0} > 0 )) || return
    local t="─── Packages  ·  no version changes  ·  ${closure_added} rebuilt "
    local n=$(( 58 - ${#t} )); (( n < 0 )) && n=0
    printf '\n%s%s\n' "$t" "${(l:n::─:)}"
    return
  fi

  # Pass 2: render. First count rows per action for the header.
  local n_updated=0 n_added=0 n_removed=0 a
  for a in "${actions[@]}"; do
    case "$a" in updated) (( n_updated++ ));; added) (( n_added++ ));; removed) (( n_removed++ ));; esac
  done

  # Column widths from the data, so the table is never wider than needed.
  #   col_name  longest package name (at least 7, "Package") + 2 spaces
  #   col_from  longest old version (at least 4, "From") + 4 spaces
  #   The To column is last, so it needs no width.
  local max_name=7 max_from=4 i  # floor = header label lengths ("Package", "From")
  for (( i=1; i<=n_total; i++ )); do
    [[ ${#names[$i]} -gt $max_name ]] && max_name=${#names[$i]}
    [[ ${#old_vers[$i]} -gt $max_from ]] && max_from=${#old_vers[$i]}
  done
  local col_name=$(( max_name + 2 )) col_from=$(( max_from + 4 ))

  # Header line: "─── Packages  ·  N updated  ·  N added  ·  N removed  ·
  # <disk change> ───…". Parts with a zero count are left out; the ─ fill
  # brings the line to 58 columns, the same width as the closing divider.
  local hparts="" j
  [[ $n_updated -gt 0 ]] && hparts="${n_updated} updated"
  [[ $n_added   -gt 0 ]] && hparts="${hparts:+${hparts}  ·  }${n_added} added"
  [[ $n_removed -gt 0 ]] && hparts="${hparts:+${hparts}  ·  }${n_removed} removed"
  [[ -n "$closure_disk" ]] && hparts="${hparts:+${hparts}  ·  }${closure_disk}"
  local htitle="─── Packages  ·  ${hparts} "
  local hfill="" hlen=$(( 58 - ${#htitle} ))
  for (( j=0; j<hlen; j++ )); do hfill="${hfill}─"; done

  # Rule under the column titles (spans both columns plus room for To) and
  # the 58-column divider that closes the block.
  local sep="" close="" sep_len=$(( col_name + col_from + 22 ))
  for (( j=0; j<sep_len; j++ )); do sep="${sep}─"; done
  for (( j=0; j<58; j++ )); do close="${close}─"; done

  # Print: header, column titles, rule, rows, footer, divider.
  echo ""
  printf '%s%s\n' "$htitle" "$hfill"
  echo ""
  printf "  %-${col_name}s  %-${col_from}s  %s\n" "Package" "From" "To"
  printf "  %s\n" "$sep"
  # Row order: notable packages first (kernel, browsers, Mesa/NVIDIA graphics,
  # systemd, Steam), then everything else in nvd's order. To promote another
  # package, add its name or glob to the (a|b|…) pattern.
  local -a order rest
  for (( i=1; i<=n_total; i++ )); do
    if [[ ${names[$i]} == (linux|linux-*|firefox*|zen*|helium*|chromium*|mesa*|systemd|nvidia*|steam*) ]]; then
      order+=($i)
    else
      rest+=($i)
    fi
  done
  for i in $order $rest; do
    printf "  %-${col_name}s  %-${col_from}s  %s\n" "${names[$i]}" "${old_vers[$i]}" "${new_vers[$i]}"
  done
  echo ""
  # Footer: store-path counts and disk usage, when nvd printed them.
  [[ -n "$closure_old" && -n "$closure_new" ]] && \
    printf "  Store paths: %s → %s  (%s new, %s removed, net %s)\n" \
      "$closure_old" "$closure_new" "$closure_added" "$closure_removed" "$closure_net"
  [[ -n "$closure_disk" ]] && printf "  Disk usage:  %s\n" "$closure_disk"
  echo ""
  printf '%s\n' "$close"
}

