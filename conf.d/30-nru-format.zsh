# ---------------------------------------------------------------------------
# NixOS management functions
#
# Config lives at ~/nixos-config (symlinked from /etc/nixos).
# The hostname is picked up automatically from the flake.
# Abbreviations for one-liner commands are defined declaratively in home.nix
# via programs.zsh.zsh-abbr.abbreviations — they expand inline before running.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# _fmt_nvd — formats nvd diff output into a clean aligned package-changes table.
#
# Collects all package data into arrays first, then renders in one pass so
# column widths can be computed from the actual data before the first row prints.
# Outputs the complete formatted block (header + table + footer + divider).
# Outputs nothing if no meaningful package changes are found.
# Handles both nvd long-form ("Added packages:") and short-form ([A]/[U]/[R]) output.
# ---------------------------------------------------------------------------
_fmt_nvd() {
  local section="" line
  # All loop variables declared here — zsh prints "var=value" if `local` is
  # re-run without assignment on an already-declared variable, so declaring
  # inside the while loop leaks values to the output.
  local pkg ver name old_v new_v rest old_vset new_vset
  local -a names=() old_vers=() new_vers=() actions=()
  local closure_old="" closure_new="" closure_added="" closure_removed="" closure_net="" closure_disk=""

  while IFS= read -r line; do
    [[ "$line" == '<<<'* || "$line" == '>>>'* ]] && continue
    [[ -z "${line// }" ]] && continue

    # Long-form section headers
    if [[ "$line" == 'Added packages:'   ]]; then section="added";   continue; fi
    if [[ "$line" == 'Removed packages:' ]]; then section="removed"; continue; fi
    if [[ "$line" == 'Version changes:'* ]]; then section="version"; continue; fi

    # Closure size line — extract all stats for the footer
    if [[ "$line" == 'Closure size:'* ]]; then
      closure_old=$(    printf '%s' "$line" | sed -E 's/Closure size: ([0-9]+).*/\1/')
      closure_new=$(    printf '%s' "$line" | sed -E 's/[^0-9]*[0-9]+ -> ([0-9]+).*/\1/')
      closure_added=$(  printf '%s' "$line" | sed -E 's/.*\(([0-9]+) paths added.*/\1/')
      closure_removed=$(printf '%s' "$line" | sed -E 's/.*, ([0-9]+) paths removed.*/\1/')
      closure_net=$(    printf '%s' "$line" | sed -E 's/.*delta ([+-]?[0-9]+).*/\1/')
      closure_disk=$(   printf '%s' "$line" | sed -E 's/.*disk usage ([^)]+)\).*/\1/')
      continue
    fi

    # Short-form prefix — update section from marker
    case "$line" in
      '[A.'*|'[A*'*|'[A+'*|'[A-'*) section="added"   ;;
      '[R.'*|'[R*'*|'[R+'*|'[R-'*) section="removed" ;;
      '[C.'*|'[C*'*|'[C+'*|'[C-'*|'[D.'*|'[D*'*|'[D+'*|'[D-'*|'[U.'*|'[U*'*|'[U+'*|'[U-'*) section="version" ;;
    esac

    case "$section" in
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
      version)
        pkg=$(printf '%s' "$line" | sed -E 's/^\[[A-Z][.*]\]  //')
        [[ -z "$pkg" ]] && continue
        pkg=$(printf '%s' "$pkg" | sed -E 's/^#[0-9]+  +//')
        [[ -z "$pkg" ]] && continue
        [[ "$pkg" != *' -> '* ]] && continue
        name="${pkg%% *}"
        rest="${pkg#"$name"}"; rest="${rest#"${rest%%[! ]*}"}"
        old_v="${rest%% -> *}"; new_v="${rest##* -> }"
        # Strip multi-output noise (", 2.63.1-man") — keep only the first version token
        old_v=$(printf '%s' "$old_v" | sed 's/, .*//')
        new_v=$(printf '%s' "$new_v" | sed 's/, .*//')
        # Skip count-only closure changes (x3 → x2) — version itself didn't change
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
  # Same-version rebuilds (git-built flake inputs) have no rows — say so instead of nothing.
  if (( n_total == 0 )); then
    (( ${closure_added:-0} > 0 )) || return
    local t="─── Packages  ·  no version changes  ·  ${closure_added} rebuilt "
    local n=$(( 58 - ${#t} )); (( n < 0 )) && n=0
    printf '\n%s%s\n' "$t" "${(l:n::─:)}"
    return
  fi

  # Count by action type
  local n_updated=0 n_added=0 n_removed=0 a
  for a in "${actions[@]}"; do
    case "$a" in updated) (( n_updated++ ));; added) (( n_added++ ));; removed) (( n_removed++ ));; esac
  done

  # Dynamic column widths — computed from actual data so the table is always tight
  local max_name=7 max_from=4 i  # floor = header label lengths ("Package", "From")
  for (( i=1; i<=n_total; i++ )); do
    [[ ${#names[$i]} -gt $max_name ]] && max_name=${#names[$i]}
    [[ ${#old_vers[$i]} -gt $max_from ]] && max_from=${#old_vers[$i]}
  done
  local col_name=$(( max_name + 2 )) col_from=$(( max_from + 4 ))

  # Section header: "─── Packages  ·  N updated  ·  +64.8 MiB ───..."
  local hparts="" j
  [[ $n_updated -gt 0 ]] && hparts="${n_updated} updated"
  [[ $n_added   -gt 0 ]] && hparts="${hparts:+${hparts}  ·  }${n_added} added"
  [[ $n_removed -gt 0 ]] && hparts="${hparts:+${hparts}  ·  }${n_removed} removed"
  [[ -n "$closure_disk" ]] && hparts="${hparts:+${hparts}  ·  }${closure_disk}"
  local htitle="─── Packages  ·  ${hparts} "
  local hfill="" hlen=$(( 58 - ${#htitle} ))
  for (( j=0; j<hlen; j++ )); do hfill="${hfill}─"; done

  # Table separator and closing divider
  local sep="" close="" sep_len=$(( col_name + col_from + 22 ))
  for (( j=0; j<sep_len; j++ )); do sep="${sep}─"; done
  for (( j=0; j<58; j++ )); do close="${close}─"; done

  # Render
  echo ""
  printf '%s%s\n' "$htitle" "$hfill"
  echo ""
  printf "  %-${col_name}s  %-${col_from}s  %s\n" "Package" "From" "To"
  printf "  %s\n" "$sep"
  # Notable packages first (kernel, browsers, graphics, init), then nvd's order.
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
  [[ -n "$closure_old" && -n "$closure_new" ]] && \
    printf "  Store paths: %s → %s  (%s new, %s removed, net %s)\n" \
      "$closure_old" "$closure_new" "$closure_added" "$closure_removed" "$closure_net"
  [[ -n "$closure_disk" ]] && printf "  Disk usage:  %s\n" "$closure_disk"
  echo ""
  printf '%s\n' "$close"
}

