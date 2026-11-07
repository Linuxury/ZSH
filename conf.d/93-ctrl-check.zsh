# ---------------------------------------------------------------------------
# ctrl-check — detect connected controllers and report their status
#
# Shows three layers that games (SDL2 / Hytale) depend on:
#   js*     — legacy joystick nodes (SDL fallback)
#   event*  — evdev nodes flagged as joystick/gamepad by udev
#   hidraw* — raw HID nodes used by sc-controller for the Steam Controller
#
# For each device: name, vendor:product ID, and whether the current user
# has access (uaccess tag or readable node). A ✓ means the game can see it;
# an ✗ means a udev rule is missing or the user isn't in the right group.
# ---------------------------------------------------------------------------
ctrl-check() {
  local bold='\e[1m' reset='\e[0m'
  local green='\e[32m' red='\e[31m' dim='\e[2m' cyan='\e[36m'

  _cc_access() {
    # Returns ✓ (green) if readable, ✗ (red) if not
    [[ -r "$1" ]] && echo "${green}✓${reset}" || echo "${red}✗${reset}"
  }

  _cc_udev_attr() {
    # Extract a udevadm property by key, e.g. ID_VENDOR_ID
    udevadm info --query=property --name="$1" 2>/dev/null \
      | grep "^${2}=" | cut -d= -f2-
  }

  echo ""
  printf "${bold}  Controller Check${reset}\n"
  printf "${dim}  ─────────────────────────────────────────────────${reset}\n"

  # ── 1. Joystick nodes (js*) ────────────────────────────────────────────
  printf "\n${cyan}${bold}  js nodes${reset}  ${dim}(legacy joystick API)${reset}\n"
  local found_js=0
  for dev in /dev/input/js*; do
    [[ -e "$dev" ]] || continue
    found_js=1
    local name vendor product
    name=$(udevadm info --query=property --name="$dev" 2>/dev/null \
           | grep '^ID_MODEL=' | cut -d= -f2-)
    vendor=$(_cc_udev_attr "$dev" ID_VENDOR_ID)
    product=$(_cc_udev_attr "$dev" ID_MODEL_ID)
    [[ -z "$name"    ]] && name="unknown"
    [[ -z "$vendor"  ]] && vendor="????"
    [[ -z "$product" ]] && product="????"
    printf "  $(_cc_access "$dev") ${bold}%-20s${reset}  ${dim}%s:%s${reset}  %s\n" \
      "$dev" "$vendor" "$product" "$name"
  done
  [[ $found_js -eq 0 ]] && printf "  ${dim}  none${reset}\n"

  # ── 2. Evdev gamepad nodes (event* with joystick/gamepad flag) ─────────
  printf "\n${cyan}${bold}  evdev nodes${reset}  ${dim}(SDL2 / game input layer)${reset}\n"
  local found_ev=0
  for dev in /dev/input/event*; do
    [[ -e "$dev" ]] || continue
    local props
    props=$(udevadm info --query=property --name="$dev" 2>/dev/null)
    echo "$props" | grep -qE '^ID_INPUT_(JOYSTICK|GAMEPAD|ACCELEROMETER)=1' || continue
    found_ev=1
    local name vendor product
    name=$(echo   "$props" | grep '^ID_MODEL='     | cut -d= -f2-)
    vendor=$(echo  "$props" | grep '^ID_VENDOR_ID=' | cut -d= -f2-)
    product=$(echo "$props" | grep '^ID_MODEL_ID='  | cut -d= -f2-)
    [[ -z "$name"    ]] && name="unknown"
    [[ -z "$vendor"  ]] && vendor="????"
    [[ -z "$product" ]] && product="????"
    printf "  $(_cc_access "$dev") ${bold}%-25s${reset}  ${dim}%s:%s${reset}  %s\n" \
      "$dev" "$vendor" "$product" "$name"
  done
  [[ $found_ev -eq 0 ]] && printf "  ${dim}  none${reset}\n"

  # ── 3. HID raw nodes (hidraw*) — sc-controller / Steam Controller ──────
  printf "\n${cyan}${bold}  hidraw nodes${reset}  ${dim}(sc-controller / HID mode)${reset}\n"
  local found_hid=0
  for dev in /dev/hidraw*; do
    [[ -e "$dev" ]] || continue
    found_hid=1
    local name vendor product
    name=$(udevadm info --query=property --name="$dev" 2>/dev/null \
           | grep '^HID_NAME=' | cut -d= -f2-)
    vendor=$(_cc_udev_attr "$dev" HID_ID)
    # HID_ID is "BUS:VENDOR:PRODUCT" — extract last two fields
    [[ -n "$vendor" ]] && product=$(echo "$vendor" | cut -d: -f3) \
                       && vendor=$(echo  "$vendor" | cut -d: -f2)
    [[ -z "$name"    ]] && name="unknown"
    [[ -z "$vendor"  ]] && vendor="????"
    [[ -z "$product" ]] && product="????"
    printf "  $(_cc_access "$dev") ${bold}%-20s${reset}  ${dim}%s:%s${reset}  %s\n" \
      "$dev" "$vendor" "$product" "$name"
  done
  [[ $found_hid -eq 0 ]] && printf "  ${dim}  none${reset}\n"

  printf "\n${dim}  ─────────────────────────────────────────────────${reset}\n"
  printf "  ${dim}✓ = readable by $USER   ✗ = missing udev rule or group${reset}\n\n"

  unfunction _cc_access _cc_udev_attr 2>/dev/null
}

