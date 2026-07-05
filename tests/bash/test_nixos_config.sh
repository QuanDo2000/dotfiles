#!/usr/bin/env bash
# Tests for tracked NixOS configuration invariants.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_greetd_launches_hyprland_through_nixos_wrapper() {
  local config_text
  config_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$config_text" "--cmd start-hyprland"
  assert_not_contains "$config_text" "--cmd Hyprland"
}

test_nixos_config_includes_pi_when_available() {
  local config_text
  config_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$config_text" "++ lib.optional (pkgs ? pi-coding-agent) pkgs.pi-coding-agent"
}
