#!/bin/bash
# Function to get the current input method name and format the output
get_status() {
  # Use fcitx5-remote to get the current input method name.
  INPUT_METHOD=$(fcitx5-remote -n | tr -d '\n')

  # Map the raw name to a friendly display name
  case "$INPUT_METHOD" in
  keyboard-us)
    echo "🇺🇸 EN"
    ;;
  unikey)
    echo "🇻🇳 VN"
    ;;
  # Default case if the name is not mapped or Fcitx is inactive
  *)
    echo "IM: ?"
    ;;
  esac
}

# Function to toggle the input method and force an update
toggle_and_update() {
  fcitx5-remote -t && get_status
}

# Main logic: Check the argument passed to the script
case "$1" in
"status")
  get_status
  ;;
"toggle")
  toggle_and_update
  ;;
*)
  # Default to showing status if no argument or an invalid argument is given
  get_status
  ;;
esac
