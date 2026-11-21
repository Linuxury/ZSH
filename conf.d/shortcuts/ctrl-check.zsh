# ===========================================================================
# conf.d/shortcuts/ctrl-check.zsh — list game controllers and whether you can read them
#
# Usage: ctrl-check        (no arguments)
# Prints three lists. Games (SDL2, Hytale) read the first two layers, and
# sc-controller uses the third for the Steam Controller:
#   js*      legacy joystick API nodes (SDL fallback)
#   event*   evdev nodes whose udev properties include ID_INPUT_JOYSTICK,
#            ID_INPUT_GAMEPAD or ID_INPUT_ACCELEROMETER set to 1
#   hidraw*  raw HID nodes
# Each device line shows: access, device path, vendor:product, name.
#   ✓  readable by the current user (test: [[ -r PATH ]])
#   ✗  not readable: the udev rule or group is missing
# A readable device is usually granted by the udev "uaccess" tag, which gives
# the logged-in seat user access.
# To turn it off: rename the file so it no longer ends in .zsh.
# ===========================================================================
ctrl-check() {
  local bold='\e[1m' reset='\e[0m'
  local green='\e[32m' red='\e[31m' dim='\e[2m' cyan='\e[36m'

  _cc_access() {
    # _cc_access PATH: print ✓ (green) if PATH is readable, else ✗ (red)
    [[ -r "$1" ]] && echo "${green}✓${reset}" || echo "${red}✗${reset}"
  }

  _cc_udev_attr() {
    # _cc_udev_attr PATH KEY: print one udev property of PATH, e.g. ID_VENDOR_ID.
    # Reads `udevadm info --query=property --name=PATH` (-q property, -n name).
    udevadm info --query=property --name="$1" 2>/dev/null \
      | grep "^${2}=" | cut -d= -f2-
  }

  echo ""
  printf "${bold}  Controller Check${reset}\n"
  printf "${dim}  ─────────────────────────────────────────────────${reset}\n"

  # ── 1. Joystick nodes (js*) ────────────────────────────────────────────
  # Name from ID_MODEL; vendor:product from ID_VENDOR_ID:ID_MODEL_ID.
  # A missing value is shown as "unknown" (name) or "????" (IDs).
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
  # All udev properties of the node are read once, then grepped. A node is
  # listed only if one of the three ID_INPUT_* flags is 1; the other event
  # nodes (keyboard, mouse) are skipped.
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
  # HID_ID is BUS:VENDOR:PRODUCT. Fields 2 and 3 become vendor and product.
  # The && chain runs only when HID_ID is set.
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

  # Remove the two helpers so they do not stay defined in the shell.
  unfunction _cc_access _cc_udev_attr 2>/dev/null
}
