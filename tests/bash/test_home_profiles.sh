#!/usr/bin/env bash
# Evaluated Home Manager profile composition tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROFILE_CACHE="$(mktemp -d)"
PROFILE_USERNAME="$(nix eval --raw --file "$REPO_DIR/config/host.nix" username)"
PROFILE_HOSTNAME="$(nix eval --raw --file "$REPO_DIR/config/host.nix" hostName)"
PROFILE_APPLY="$(<"$REPO_DIR/tests/nix/profile-summary.nix")"
trap 'rm -rf "$PROFILE_CACHE"' EXIT

setup() { init_test_env; }
teardown() { cleanup_test_env; }

_profile_expr() { printf 'homeConfigurations."%s@%s".config' "$PROFILE_USERNAME" "$1"; }
_profile_summary() {
  local profile="$1" expression cache="$PROFILE_CACHE/$1.json"
  if [[ ! -f "$cache" ]]; then
    case "$profile" in
      linux|arch-server) expression="$(_profile_expr "$profile")" ;;
      nixos) expression="nixosConfigurations.\"$PROFILE_HOSTNAME\".config.home-manager.users.$PROFILE_USERNAME" ;;
      darwin) expression="darwinConfigurations.mac.config.home-manager.users.$PROFILE_USERNAME" ;;
      *) return 1 ;;
    esac
    nix eval --json "path:$REPO_DIR#$expression" --apply "$PROFILE_APPLY" > "$cache" || return
  fi
  cat "$cache"
}
_profile_lines() { _profile_summary "$1" | jq -r ".$2[]" | sort -u; }
_profile_packages() { _profile_lines "$1" packages; }
_profile_services() { _profile_lines "$1" services; }
_profile_timers() { _profile_lines "$1" timers; }
_profile_files() { _profile_lines "$1" files; }
_profile_wanted() { _profile_summary "$1" | jq -r --arg unit "$2" '.serviceWanted[$unit][]' | sort; }
_profile_timer_wanted() { _profile_summary "$1" | jq -r --arg unit "$2" '.timerWanted[$unit][]' | sort; }
_profile_marker() { _profile_summary "$1" | jq -r '.marker'; }
_profile_xdg_files() { _profile_lines "$1" xdgFiles; }
_profile_activation() { _profile_summary "$1" | jq -r --arg name "$2" '.activations[$name]'; }
_profile_file_meta() { _profile_summary "$1" | jq -c --arg path "$2" '.fileMeta[$path]'; }
_profile_program() { _profile_summary "$1" | jq -r --arg name "$2" '.programs[$name]'; }
_profile_service() { _profile_summary "$1" | jq -c --arg name "$2" '.serviceAttrs[$name]'; }
_profile_timer() { _profile_summary "$1" | jq -c --arg name "$2" '.timerAttrs[$name]'; }

assert_line_present() { grep -Fxq "$2" <<< "$1" || echo "  expected line missing: $2" >> "$ERROR_FILE"; return 0; }
assert_line_absent() { grep -Fxq "$2" <<< "$1" && echo "  unexpected line present: $2" >> "$ERROR_FILE"; return 0; }
_test_present() { local text="$1" item; shift; for item in "$@"; do assert_line_present "$text" "$item"; done; }
_test_absent() { local text="$1" item; shift; for item in "$@"; do assert_line_absent "$text" "$item"; done; }

common_packages=(bash-language-server codex nil pi-coding-agent ShellCheck statix)
desktop_packages=(ghostty google-chrome grim hyprshutdown pavucontrol playerctl rbw slurp wl-clipboard)
system_desktop_packages=(pinentry-gnome3 thunar xarchiver)
personal_packages=(anki-with-addons obsidian webcord)
sync_packages=(obsidian-headless rclone)
arch_sync_packages=(obsidian-headless rclone)
storage_packages=(restic)
desktop_services=(hyprpolkitagent hyprsunset wl-clip-persist)
arch_services=(obsidian-sync google-drive-mount google-drive-bisync google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance)
arch_timers=(google-drive-bisync google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance)

_test_present_array() { _test_present "$1" "${@:2}"; }
_test_absent_array() { _test_absent "$1" "${@:2}"; }

test_profile_packages_and_services_are_composed_by_role() {
  local generic_packages arch_packages generic_service_names arch_service_names
  generic_packages="$(_profile_packages linux)"; arch_packages="$(_profile_packages arch-server)"
  generic_service_names="$(_profile_services linux)"; arch_service_names="$(_profile_services arch-server)"
  _test_present_array "$generic_packages" "${common_packages[@]}"
  _test_present "$generic_packages" gcc-wrapper fontconfig git jq nerd-fonts-fira-code openssh
  _test_absent_array "$generic_packages" vtsls "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}" "${storage_packages[@]}"
  _test_present_array "$arch_packages" "${common_packages[@]}" fontconfig git jq nerd-fonts-fira-code openssh "${arch_sync_packages[@]}" "${storage_packages[@]}"
  _test_absent_array "$arch_packages" gcc-wrapper "${desktop_packages[@]}" "${personal_packages[@]}"
  _test_absent "$generic_service_names" "${arch_services[@]}" "${desktop_services[@]}"
  _test_present "$arch_service_names" "${arch_services[@]}"; _test_absent "$arch_service_names" "${desktop_services[@]}"
}

test_nixos_and_darwin_packages_and_services_are_composed_by_role() {
  local nixos_packages nixos_services nixos_timers darwin_packages darwin_services darwin_timers
  nixos_packages=$(_profile_packages nixos); nixos_services=$(_profile_services nixos); nixos_timers=$(_profile_timers nixos)
  darwin_packages=$(_profile_packages darwin); darwin_services=$(_profile_services darwin); darwin_timers=$(_profile_timers darwin)
  _test_present_array "$nixos_packages" "${common_packages[@]}" gcc-wrapper git jq "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}"; _test_absent "$nixos_packages" restic "${system_desktop_packages[@]}"
  _test_present "$nixos_services" obsidian-sync google-drive-mount google-drive-bisync "${desktop_services[@]}"; _test_absent "$nixos_services" google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance
  _test_present "$nixos_timers" google-drive-bisync; _test_absent "$nixos_timers" google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance
  _test_present "$darwin_packages" "${common_packages[@]}" git jq nerd-fonts-fira-code; _test_absent_array "$darwin_packages" "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}" "${storage_packages[@]}"
  _test_absent "$darwin_services" "${arch_services[@]}" "${desktop_services[@]}"; _test_absent "$darwin_timers" "${arch_timers[@]}"
}

test_profile_files_and_markers_are_composed_by_role() {
  local generic_files arch_files nixos_files darwin_files generic_marker arch_marker nixos_marker darwin_marker
  generic_files=$(_profile_files linux); arch_files=$(_profile_files arch-server); nixos_files=$(_profile_files nixos); darwin_files=$(_profile_files darwin)
  _test_absent "$generic_files" 'Documents/Sync/.obsidian/app.json' '.config/ghostty/config'; _test_absent "$arch_files" 'Documents/Sync/.obsidian/app.json' '.config/ghostty/config'; assert_line_present "$nixos_files" 'Documents/Sync/.obsidian/app.json'; assert_line_present "$nixos_files" '.config/dotfiles/profile'; _test_absent "$darwin_files" 'Documents/Sync/.obsidian/app.json'; assert_line_present "$darwin_files" '.config/dotfiles/profile'
  generic_marker=$(_profile_marker linux); arch_marker=$(_profile_marker arch-server)
  nixos_marker=$(_profile_marker nixos); darwin_marker=$(_profile_marker darwin)
  for flag in desktop personalApps obsidianSync googleDriveSync storageOffsiteBackup; do assert_contains "$generic_marker" "$flag=false"; done
  assert_contains "$arch_marker" 'desktop=false'; assert_contains "$arch_marker" 'personalApps=false'; assert_contains "$arch_marker" 'obsidianSync=true'; assert_contains "$arch_marker" 'googleDriveSync=true'; assert_contains "$arch_marker" 'storageOffsiteBackup=true'
  assert_contains "$nixos_marker" 'desktop=true'; assert_contains "$nixos_marker" 'personalApps=true'; assert_contains "$nixos_marker" 'obsidianSync=true'; assert_contains "$nixos_marker" 'googleDriveSync=true'; assert_contains "$nixos_marker" 'storageOffsiteBackup=false'
  for flag in desktop personalApps obsidianSync googleDriveSync storageOffsiteBackup; do assert_contains "$darwin_marker" "$flag=false"; done
}

test_profile_disables_pi_memory_exit_summary() {
  local profile
  for profile in linux arch-server nixos darwin; do
    assert_equals 0 "$(_profile_summary "$profile" | jq -r '.sessionVariables.PI_MEMORY_EXIT_SUMMARY')"
  done
}

test_profile_activation_targets_are_complete() {
  local wanted unit
  for unit in obsidian-sync google-drive-mount; do wanted=$(_profile_wanted arch-server "$unit"); assert_line_present "$wanted" default.target; done
  for unit in "${arch_timers[@]}"; do wanted=$(_profile_timer_wanted arch-server "$unit"); assert_line_present "$wanted" timers.target; done
  wanted=$(_profile_wanted nixos obsidian-sync); assert_line_present "$wanted" default.target
  wanted=$(_profile_wanted nixos google-drive-mount); assert_line_present "$wanted" default.target
  wanted=$(_profile_timer_wanted nixos google-drive-bisync); assert_line_present "$wanted" timers.target
}

test_profile_desktop_units_and_nixos_fuse_wrapper() {
  local generic arch nixos_wrappers
  local wrapper_expr="nixosConfigurations.\"$PROFILE_HOSTNAME\".config.security.wrappers"
  generic=$(_profile_services linux); arch=$(_profile_services arch-server); nixos_wrappers=$(nix eval --json "path:$REPO_DIR#$wrapper_expr" | jq -r 'keys[]')
  _test_absent "$generic" "${desktop_services[@]}"; _test_absent "$arch" "${desktop_services[@]}"; assert_line_present "$nixos_wrappers" fusermount3
}

test_evaluated_profile_configures_runtime_files_and_activations() {
  local nixos_files arch_files activations
  nixos_files=$(_profile_files nixos); arch_files=$(_profile_files arch-server)
  _test_present "$nixos_files" '.hermes/SOUL.md' '.agents/skills/systematic-debugging' '.agents/skills/test-driven-development' '.agents/skills/skill-retrospective' '.pi/agent/extensions/autoresearch' '.pi/agent/extensions/fast-mode' '.local/bin/bitwarden-picker' '.local/bin/input-method-status' '.local/bin/hyprsunset-status' '.local/bin/show-keybinds'
  _test_present "$arch_files" '.hermes/SOUL.md' '.agents/skills/systematic-debugging' '.agents/skills/test-driven-development' '.agents/skills/skill-retrospective' '.pi/agent/extensions/autoresearch' '.pi/agent/extensions/fast-mode' '.local/bin/restic-recover'
  local activation
  activation=$(_profile_activation nixos seedPiConfigs)
  for seed in 'settings.json' 'keybindings.json' 'web-search.json:../web-search.json' 'mcp.json'; do
    assert_contains "$activation" "$seed"
  done
  assert_equals true "$(_profile_file_meta nixos '.pi/agent/extensions/autoresearch' | jq -r .force)"
  assert_equals true "$(_profile_file_meta darwin '.pi/agent/extensions/autoresearch' | jq -r .force)"
  assert_equals true "$(_profile_file_meta nixos '.pi/agent/extensions/fast-mode' | jq -r .force)"
  assert_equals true "$(_profile_file_meta darwin '.pi/agent/extensions/fast-mode' | jq -r .force)"
  assert_equals true "$(_profile_file_meta nixos '.hermes/SOUL.md' | jq -r .force)"
  assert_contains "$(_profile_file_meta nixos '.hermes/SOUL.md')" 'SOUL.md'
}

test_evaluated_profile_configures_desktop_and_storage_settings() {
  local nixos arch generic
  nixos=$(_profile_summary nixos); arch=$(_profile_summary arch-server); generic=$(_profile_summary linux)
  assert_equals true "$(jq -r '.programs.fuzzel' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.waybar' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.waybarSystemd' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.wlClipPersist' <<<"$nixos")"
  assert_equals regular "$(jq -r '.programs.wlClipPersistType' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.mako' <<<"$nixos")"
  assert_equals 'ghostty' "$(jq -r '.programs.fuzzelSettings.main.terminal' <<<"$nixos")"
  assert_equals 'uwsm app --' "$(jq -r '.programs.fuzzelSettings.main."launch-prefix"' <<<"$nixos")"
  assert_equals 'DP-3' "$(jq -r '.programs.makoSettings.output' <<<"$nixos")"
  assert_equals 5000 "$(jq -r '.programs.makoSettings."default-timeout"' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.hyprpolkitagent' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.hyprsunset' <<<"$nixos")"
  assert_equals true "$(jq -r '.programs.rclone' <<<"$arch")"
  assert_equals false "$(jq -r '.programs.rclone' <<<"$generic")"
  assert_equals true "$(jq -r '.userDirs.enable' <<<"$nixos")"
  assert_equals '/home/quando/Documents' "$(jq -r '.userDirs.documents' <<<"$nixos")"
  assert_equals '/home/quando/Downloads' "$(jq -r '.userDirs.download' <<<"$nixos")"
  assert_equals null "$(jq -r '.userDirs.desktop' <<<"$nixos")"
  assert_equals thunar.desktop "$(jq -r '.mimeDefaults."inode/directory"[0]' <<<"$nixos")"
  assert_equals google-chrome.desktop "$(jq -r '.mimeDefaults."x-scheme-handler/https"[0]' <<<"$nixos")"
  assert_equals xarchiver.desktop "$(jq -r '.mimeDefaults."application/zip"[0]' <<<"$nixos")"
  assert_equals true "$(_profile_file_meta nixos '/home/quando/.config/jj/config.toml' | jq -r .force)"
  assert_equals '[]' "$(jq -c '.programs.tmuxPlugins' <<<"$nixos")"
  _test_present "$(jq -r '.xdgFiles[]' <<<"$nixos")" ghostty/config
  _test_absent "$(jq -r '.xdgFiles[]' <<<"$generic")" ghostty/config
}

test_evaluated_profile_service_security_and_schedule() {
  local service_name service timer command
  for service_name in google-drive-bisync google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance obsidian-sync; do
    service=$(_profile_service arch-server "$service_name")
    assert_equals true "$(jq -r .noNewPrivileges <<<"$service")"
    assert_equals true "$(jq -r .restrictSUIDSGID <<<"$service")"
    assert_equals true "$(jq -r .restrictRealtime <<<"$service")"
    assert_equals true "$(jq -r .lockPersonality <<<"$service")"
    assert_equals native "$(jq -r .systemCallArchitectures <<<"$service")"
    assert_contains "$(jq -r '.restrictAddressFamilies[]' <<<"$service")" AF_INET
  done
  service=$(_profile_service arch-server google-drive-mount)
  assert_equals false "$(jq -r .noNewPrivileges <<<"$service")"
  assert_equals false "$(jq -r .restrictSUIDSGID <<<"$service")"
  assert_equals '0077' "$(jq -r .umask <<<"$service")"
  assert_contains "$(jq -r '.execStart[]' <<<"$service")" '--file-perms 0600 --dir-perms 0700'
  service=$(_profile_service arch-server google-drive-bisync)
  assert_equals 'Google Drive two-way sync' "$(jq -r .description <<<"$service")"
  assert_equals '65m' "$(jq -r .timeoutStart <<<"$service")"
  assert_contains "$(jq -r '.conditionPaths[]' <<<"$service")" rclone.conf
  command=$(jq -r '.execStart[]' <<<"$service")
  assert_contains "$command" google-drive-sync.lock
  assert_contains "$command" rclone
  assert_contains "$(jq -r .execStopPost <<<"$service")" chmod
  service=$(_profile_service arch-server google-drive-storage-sync)
  assert_equals infinity "$(jq -r .timeoutStart <<<"$service")"
  assert_equals '/mnt/storage' "$(jq -r .conditionMount <<<"$service")"
  service=$(_profile_service arch-server storage-offsite-backup)
  assert_equals '/mnt/storage' "$(jq -r .conditionMount <<<"$service")"
  assert_contains "$(jq -r '.conditionDirectories[]' <<<"$service")" '/mnt/storage/Storage/Documents'
  assert_contains "$(jq -r '.execStart[]' <<<"$service")" '/mnt/storage/Storage/Music'
  assert_contains "$(jq -r '.environment[]' <<<"$service")" 'RESTIC_REPOSITORY=rclone:gdrive:ServerBackup/restic'
  timer=$(_profile_timer arch-server google-drive-bisync)
  assert_equals null "$(jq -r .calendar <<<"$timer")"
  assert_equals 'timers.target' "$(jq -r '.wantedBy[0]' <<<"$timer")"
  assert_equals '5m' "$(jq -r .onActive <<<"$timer")"
  assert_equals true "$(jq -r .persistent <<<"$timer")"
  assert_equals daily "$(_profile_timer arch-server google-drive-storage-sync | jq -r .calendar)"
  assert_equals '*-*-* 06:00:00' "$(_profile_timer arch-server storage-offsite-backup | jq -r .calendar)"
  assert_equals '*-*-08 07:00:00' "$(_profile_timer arch-server storage-offsite-maintenance | jq -r .calendar)"
}

test_platform_profiles_have_expected_ghostty_config() {
  local generic_files arch_files nixos_config darwin_config
  generic_files=$(_profile_files linux); arch_files=$(_profile_files arch-server); nixos_config=$(_profile_xdg_files nixos); darwin_config=$(_profile_xdg_files darwin)
  _test_absent "$generic_files" '.config/ghostty/config'; _test_absent "$arch_files" '.config/ghostty/config'; assert_line_present "$nixos_config" ghostty/config; assert_line_present "$darwin_config" ghostty/config
}
