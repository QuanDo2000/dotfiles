#!/usr/bin/env bash
# Evaluated Home Manager profile composition tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  PROFILE_CACHE="$TEST_TMPDIR/profile-cache"
  mkdir -p "$PROFILE_CACHE"
  PROFILE_USERNAME="$(nix eval --raw --file "$REPO_DIR/config/host.nix" username)"
  PROFILE_HOSTNAME="$(nix eval --raw --file "$REPO_DIR/config/host.nix" hostName)"
}
teardown() { cleanup_test_env; }

_eval_cached() {
  local expression="$2" cache="$PROFILE_CACHE/$1.json"
  if [[ ! -f "$cache" ]]; then
    nix eval --json "path:$REPO_DIR#$expression" > "$cache" || return
  fi
  cat "$cache"
}
_profile_expr() { printf 'homeConfigurations."%s@%s"' "$PROFILE_USERNAME" "$1"; }
_profile_packages() {
  local profile="$1" expr
  expr=$(_profile_expr "$profile").config.home.packages
  nix eval --json "path:$REPO_DIR#$expr" \
    --apply 'xs: map (x: if x ? pname then x.pname else (builtins.parseDrvName x.name).name) xs' \
    | jq -r '.[]' | sort -u
}
_profile_services() { local profile="$1" expr; expr=$(_profile_expr "$profile").config.systemd.user.services; _eval_cached "$profile-services" "$expr" | jq -r 'keys[]' | sort; }
_profile_timers() { local profile="$1" expr; expr=$(_profile_expr "$profile").config.systemd.user.timers; _eval_cached "$profile-timers" "$expr" | jq -r 'keys[]' | sort; }
_profile_files() { local profile="$1" expr; expr=$(_profile_expr "$profile").config.home.file; _eval_cached "$profile-files" "$expr" | jq -r 'keys[]' | sort; }
_profile_wanted() {
  local profile="$1" unit="$2" expr
  expr=$(_profile_expr "$profile").config.systemd.user.services.\"$unit\".Install.WantedBy
  _eval_cached "$profile-$unit-wanted" "$expr" | jq -r '.[]' | sort
}
_profile_timer_wanted() {
  local profile="$1" unit="$2" expr
  expr=$(_profile_expr "$profile").config.systemd.user.timers.\"$unit\".Install.WantedBy
  _eval_cached "$profile-$unit-timer-wanted" "$expr" | jq -r '.[]' | sort
}
_nixos_expr() { printf 'nixosConfigurations."%s".config.home-manager.users.%s' "$PROFILE_HOSTNAME" "$PROFILE_USERNAME"; }
_nixos_json() { local expr; expr=$(_nixos_expr).$1; nix eval --json "path:$REPO_DIR#$expr"; }
_nixos_packages() {
  local expr; expr=$(_nixos_expr).home.packages
  nix eval --json "path:$REPO_DIR#$expr" \
    --apply 'xs: map (x: if x ? pname then x.pname else (builtins.parseDrvName x.name).name) xs' \
    | jq -r '.[]' | sort -u
}
_darwin_packages() {
  nix eval --json "path:$REPO_DIR#darwinConfigurations.mac.config.home-manager.users.$PROFILE_USERNAME.home.packages" \
    --apply 'xs: map (x: if x ? pname then x.pname else (builtins.parseDrvName x.name).name) xs' \
    | jq -r '.[]' | sort -u
}
_darwin_json() { nix eval --json "path:$REPO_DIR#darwinConfigurations.mac.config.home-manager.users.$PROFILE_USERNAME.$1"; }

assert_line_present() { grep -Fxq "$2" <<< "$1" || echo "  expected line missing: $2" >> "$ERROR_FILE"; return 0; }
assert_line_absent() { grep -Fxq "$2" <<< "$1" && echo "  unexpected line present: $2" >> "$ERROR_FILE"; return 0; }
_test_present() { local text="$1" item; shift; for item in "$@"; do assert_line_present "$text" "$item"; done; }
_test_absent() { local text="$1" item; shift; for item in "$@"; do assert_line_absent "$text" "$item"; done; }

common_packages=(bash-language-server codex codebase-memory-mcp fff-mcp jq nil pi-coding-agent ShellCheck statix vtsls)
desktop_packages=(ghostty google-chrome grim hyprshutdown pavucontrol playerctl rbw slurp thunar wl-clipboard xarchiver)
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
  _test_absent_array "$generic_packages" "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}" "${storage_packages[@]}"
  _test_present_array "$arch_packages" "${common_packages[@]}" "${arch_sync_packages[@]}" "${storage_packages[@]}"
  _test_absent_array "$arch_packages" "${desktop_packages[@]}" "${personal_packages[@]}"
  _test_absent "$generic_service_names" "${arch_services[@]}" "${desktop_services[@]}"
  _test_present "$arch_service_names" "${arch_services[@]}"; _test_absent "$arch_service_names" "${desktop_services[@]}"
}

test_nixos_and_darwin_packages_and_services_are_composed_by_role() {
  local nixos_packages nixos_services nixos_timers darwin_packages darwin_services darwin_timers
  nixos_packages=$(_nixos_packages); nixos_services=$(_nixos_json systemd.user.services | jq -r 'keys[]' | sort); nixos_timers=$(_nixos_json systemd.user.timers | jq -r 'keys[]' | sort)
  darwin_packages=$(_darwin_packages); darwin_services=$(_darwin_json systemd.user.services | jq -r 'keys[]' | sort); darwin_timers=$(_darwin_json systemd.user.timers | jq -r 'keys[]' | sort)
  _test_present_array "$nixos_packages" "${common_packages[@]}" "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}"; _test_absent "$nixos_packages" restic
  _test_present "$nixos_services" obsidian-sync google-drive-mount google-drive-bisync "${desktop_services[@]}"; _test_absent "$nixos_services" google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance
  _test_present "$nixos_timers" google-drive-bisync; _test_absent "$nixos_timers" google-drive-storage-sync storage-offsite-backup storage-offsite-maintenance
  _test_present "$darwin_packages" "${common_packages[@]}"; _test_absent_array "$darwin_packages" "${desktop_packages[@]}" "${personal_packages[@]}" "${sync_packages[@]}" "${storage_packages[@]}"
  _test_absent "$darwin_services" "${arch_services[@]}" "${desktop_services[@]}"; _test_absent "$darwin_timers" "${arch_timers[@]}"
}

test_profile_files_and_markers_are_composed_by_role() {
  local generic_files arch_files nixos_files darwin_files generic_marker arch_marker nixos_marker darwin_marker
  generic_files=$(_profile_files linux); arch_files=$(_profile_files arch-server); nixos_files=$(_nixos_json home.file | jq -r 'keys[]' | sort); darwin_files=$(_darwin_json home.file | jq -r 'keys[]' | sort)
  _test_absent "$generic_files" 'Documents/Sync/.obsidian/app.json' '.config/ghostty/config'; _test_absent "$arch_files" 'Documents/Sync/.obsidian/app.json' '.config/ghostty/config'; assert_line_present "$nixos_files" 'Documents/Sync/.obsidian/app.json'; assert_line_present "$nixos_files" '.config/dotfiles/profile'; _test_absent "$darwin_files" 'Documents/Sync/.obsidian/app.json'; assert_line_present "$darwin_files" '.config/dotfiles/profile'
  local marker_expr
  marker_expr=$(_profile_expr linux).config.home.file.\".config/dotfiles/profile\".text; generic_marker=$(nix eval --raw "path:$REPO_DIR#$marker_expr")
  marker_expr=$(_profile_expr arch-server).config.home.file.\".config/dotfiles/profile\".text; arch_marker=$(nix eval --raw "path:$REPO_DIR#$marker_expr")
  nixos_marker=$(_nixos_json 'home.file.".config/dotfiles/profile".text' 2>/dev/null || true)
  darwin_marker=$(_darwin_json 'home.file.".config/dotfiles/profile".text' 2>/dev/null || true)
  for flag in desktop personalApps obsidianSync googleDriveSync storageOffsiteBackup; do assert_contains "$generic_marker" "$flag=false"; done
  assert_contains "$arch_marker" 'desktop=false'; assert_contains "$arch_marker" 'personalApps=false'; assert_contains "$arch_marker" 'obsidianSync=true'; assert_contains "$arch_marker" 'googleDriveSync=true'; assert_contains "$arch_marker" 'storageOffsiteBackup=true'
  assert_contains "$nixos_marker" 'desktop=true'; assert_contains "$nixos_marker" 'personalApps=true'; assert_contains "$nixos_marker" 'obsidianSync=true'; assert_contains "$nixos_marker" 'googleDriveSync=true'; assert_contains "$nixos_marker" 'storageOffsiteBackup=false'
  for flag in desktop personalApps obsidianSync googleDriveSync storageOffsiteBackup; do assert_contains "$darwin_marker" "$flag=false"; done
}

test_profile_activation_targets_are_complete() {
  local wanted unit
  for unit in obsidian-sync google-drive-mount; do wanted=$(_profile_wanted arch-server "$unit"); assert_line_present "$wanted" default.target; done
  for unit in "${arch_timers[@]}"; do wanted=$(_profile_timer_wanted arch-server "$unit"); assert_line_present "$wanted" timers.target; done
  wanted=$(_nixos_json 'systemd.user.services."obsidian-sync".Install.WantedBy' | jq -r '.[]'); assert_line_present "$wanted" default.target
  wanted=$(_nixos_json 'systemd.user.services."google-drive-mount".Install.WantedBy' | jq -r '.[]'); assert_line_present "$wanted" default.target
  wanted=$(_nixos_json 'systemd.user.timers."google-drive-bisync".Install.WantedBy' | jq -r '.[]'); assert_line_present "$wanted" timers.target
}

test_profile_desktop_units_and_nixos_fuse_wrapper() {
  local generic arch nixos_wrappers
  local wrapper_expr="nixosConfigurations.\"$PROFILE_HOSTNAME\".config.security.wrappers"
  generic=$(_profile_services linux); arch=$(_profile_services arch-server); nixos_wrappers=$(_eval_cached nixos-wrappers "$wrapper_expr" | jq -r 'keys[]')
  _test_absent "$generic" "${desktop_services[@]}"; _test_absent "$arch" "${desktop_services[@]}"; assert_line_present "$nixos_wrappers" fusermount3
}

test_platform_profiles_have_expected_ghostty_config() {
  local generic_files arch_files nixos_config darwin_config
  generic_files=$(_profile_files linux); arch_files=$(_profile_files arch-server); nixos_config=$(_nixos_json xdg.configFile | jq -r 'keys[]' | sort); darwin_config=$(_darwin_json xdg.configFile | jq -r 'keys[]' | sort)
  _test_absent "$generic_files" '.config/ghostty/config'; _test_absent "$arch_files" '.config/ghostty/config'; assert_line_present "$nixos_config" ghostty/config; assert_line_present "$darwin_config" ghostty/config
}
