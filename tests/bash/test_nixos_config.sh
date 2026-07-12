#!/usr/bin/env bash
# Tests for tracked NixOS configuration invariants.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_greetd_launches_hyprland_through_nixos_wrapper() {
  local config_text
  config_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$config_text" "--cmd start-hyprland"
  assert_not_contains "$config_text" "--cmd Hyprland"
}

test_hyprland_launches_obsidian_with_super_n() {
  local hypr_text
  hypr_text="$(<"$REPO_DIR/config/unix/config/hypr/hyprland.lua")"

  assert_contains "$hypr_text" 'hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("obsidian"))'
}

test_flake_uses_flat_nix_config_files() {
  local flake_text
  flake_text="$(<"$REPO_DIR/flake.nix")"

  assert_file_exists "$REPO_DIR/config/home.nix"
  assert_file_exists "$REPO_DIR/config/host.nix"
  assert_file_exists "$REPO_DIR/config/hardware-configuration.nix"
  assert_file_exists "$REPO_DIR/config/darwin.nix"
  assert_contains "$flake_text" "./config/home.nix"
  assert_contains "$flake_text" "./config/nixos/configuration.nix"
  assert_contains "$flake_text" "./config/darwin.nix"
  assert_contains "$flake_text" "machine = import ./config/host.nix"
  assert_contains "$flake_text" '"${machine.hostName}" = nixpkgs.lib.nixosSystem'
  assert_contains "$flake_text" "\"\${machine.username}@linux\""
  assert_not_contains "$flake_text" "\"\${machine.username}@arch\""
  assert_contains "$flake_text" "config.allowUnfree = true"
  assert_contains "$flake_text" "apps.x86_64-linux.home-manager"
  assert_contains "$flake_text" "apps.aarch64-darwin.darwin-rebuild"
  assert_contains "$flake_text" "darwinPkgs = import nixpkgs"
  assert_contains "$flake_text" "packages.aarch64-darwin.codex"
  assert_contains "$flake_text" "packages.x86_64-linux.obsidian-headless"
  assert_contains "$flake_text" "devShells.x86_64-linux.default"
  assert_contains "$flake_text" "gh"
  assert_contains "$flake_text" "powershell"
  assert_not_contains "$flake_text" "config/nix/"
}

test_codex_package_supports_darwin_release_wheel() {
  local codex_text
  codex_text="$(<"$REPO_DIR/packages/codex-release.nix")"

  assert_contains "$codex_text" "linuxHash"
  assert_contains "$codex_text" "darwinHash"
  assert_contains "$codex_text" "codex-package-x86_64-unknown-linux-musl.tar.gz"
  assert_contains "$codex_text" "openai_codex_cli_bin-\${version}-py3-none-macosx_11_0_arm64.whl"
  assert_contains "$codex_text" "codex_cli_bin"
  assert_contains "$codex_text" "aarch64-darwin"
  assert_contains "$codex_text" "unzip"
}

test_pi_matches_minimal_codex_setup() {
  local home_text pi_package pi_settings fff_package codex_config global_agents
  home_text="$(<"$REPO_DIR/config/home.nix")"
  pi_package="$(<"$REPO_DIR/packages/pi-agent.nix")"
  pi_settings="$(<"$REPO_DIR/config/shared/ai/pi/settings.json")"
  fff_package="$(<"$REPO_DIR/packages/fff-mcp.nix")"
  codex_config="$(<"$REPO_DIR/config/shared/ai/codex/config.toml")"
  global_agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"

  assert_contains "$home_text" "pi-agent = pkgs.callPackage ../packages/pi-agent.nix"
  assert_contains "$home_text" "pi-agent"
  assert_contains "$home_text" "home.activation.seedPiSettings"
  assert_contains "$home_text" "./shared/ai/pi/settings.json"
  assert_contains "$pi_package" 'version = "0.80.6"'
  assert_contains "$pi_package" "@earendil-works/pi-coding-agent"
  assert_contains "$pi_package" '${lib.getExe jq} '\''del(.devDependencies)'\'' package.json'
  assert_not_contains "$pi_package" "nativeBuildInputs = [ jq ]"
  assert_equals "openai-codex" "$(jq -r '.defaultProvider' <<< "$pi_settings")"
  assert_equals "gpt-5.6-sol" "$(jq -r '.defaultModel' <<< "$pi_settings")"
  assert_equals "medium" "$(jq -r '.defaultThinkingLevel' <<< "$pi_settings")"
  assert_equals "ask" "$(jq -r '.defaultProjectTrust' <<< "$pi_settings")"
  assert_equals "~/.agents/skills" "$(jq -r '.skills[]' <<< "$pi_settings")"
  assert_contains "$pi_settings" '"npm:pi-mcp-extension@1.5.0"'
  assert_contains "$pi_settings" '"npm:@dietrichgebert/ponytail@4.8.4"'
  assert_contains "$pi_settings" '"npm:pi-hermes-memory@0.7.23"'
  assert_contains "$pi_settings" '"npm:@ff-labs/pi-fff@0.9.6"'
  assert_contains "$fff_package" 'version = "0.9.6"'
  assert_contains "$fff_package" 'target = "x86_64-unknown-linux-musl"'
  assert_contains "$fff_package" 'target = "aarch64-apple-darwin"'
  assert_contains "$codex_config" '[mcp_servers.fff]'
  assert_contains "$codex_config" 'args = ["fff-mcp"]'
  assert_contains "$global_agents" 'Use codebase-memory first when it is available'
  assert_contains "$global_agents" 'fall back to FFF'
  assert_contains "$home_text" '".codex/AGENTS.md" = forceSource ./shared/ai/AGENTS.md'
  assert_contains "$home_text" '".pi/agent/AGENTS.md" = forceSource ./shared/ai/AGENTS.md'
  assert_contains "$home_text" 'home.activation.seedPiMcpConfig'
  assert_contains "$home_text" './shared/ai/pi/mcp.json'
  assert_contains "$home_text" '${../scripts/pi_seed_merge.py}'
  assert_contains "$home_text" 'Warning: failed to sync Codex config seed'
  assert_contains "$home_text" 'Warning: failed to sync Pi settings seed'
  assert_contains "$home_text" 'Warning: failed to sync Pi MCP config seed'
  assert_contains "$home_text" "merge_source=\"''\${apply_seed:-\$source}\""
  assert_not_contains "$home_text" '".pi/agent/extensions/codebase-memory-guidance.ts"'
  assert_contains "$home_text" '".pi/agent/extensions/codex-status.js"'
  assert_not_contains "$codex_config" 'SessionStart ='
  assert_not_contains "$codex_config" '[hooks'

  local pi_mcp
  pi_mcp="$(<"$REPO_DIR/config/shared/ai/pi/mcp.json")"
  assert_equals "codebase-memory-mcp" "$(jq -r '.mcpServers.codebaseMemory.command' <<< "$pi_mcp")"
  assert_equals "eager" "$(jq -r '.mcpServers.codebaseMemory.lifecycle' <<< "$pi_mcp")"
  assert_equals "null" "$(jq -r '.mcpServers.fff // null' <<< "$pi_mcp")"
}

test_nixos_uses_tracked_host_config() {
  local host_text flake_text configuration_text
  host_text="$(<"$REPO_DIR/config/host.nix")"
  flake_text="$(<"$REPO_DIR/flake.nix")"
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$host_text" 'username = "quando"'
  assert_contains "$host_text" 'hostName = "nixos"'
  assert_contains "$host_text" 'timeZone = "America/Los_Angeles"'
  assert_contains "$host_text" 'stateVersion = "26.05"'
  assert_contains "$flake_text" 'nixosConfigurations."${machine.hostName}"'
  assert_contains "$configuration_text" "import ../host.nix"
  assert_not_contains "$configuration_text" "/etc/nixos/machine.nix"
}

test_nixos_opens_ssh_firewall_through_openssh() {
  local configuration_text
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$configuration_text" "services.openssh = {"
  assert_contains "$configuration_text" "openFirewall = true"
  assert_not_contains "$configuration_text" "networking.firewall.allowedTCPPorts = [ 22 ];"
}

test_darwin_uses_tracked_host_username() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$darwin_text" "machine = import ./host.nix"
  assert_contains "$darwin_text" "system.primaryUser = machine.username"
  assert_contains "$darwin_text" "users.users.\${machine.username} = {"
  assert_contains "$darwin_text" "home = \"/Users/\${machine.username}\""
  assert_contains "$darwin_text" "shell = pkgs.zsh"
  assert_contains "$darwin_text" "home-manager.users.\${machine.username}"
  assert_not_contains "$darwin_text" 'system.primaryUser = "quando"'
  assert_not_contains "$darwin_text" "users.users.quando"
  assert_not_contains "$darwin_text" "home-manager.users.quando"
}

test_nixos_uses_tracked_hardware_config() {
  local hardware_text configuration_text
  hardware_text="$(<"$REPO_DIR/config/hardware-configuration.nix")"
  configuration_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$hardware_text" 'nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"'
  assert_contains "$hardware_text" 'fileSystems."/"'
  assert_contains "$configuration_text" "../hardware-configuration.nix"
  assert_not_contains "$configuration_text" "/etc/nixos/hardware-configuration.nix"
}

test_home_config_uses_program_home_manager_cli() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "home.packages"
  assert_contains "$home_text" "programs.home-manager.enable = true"
  assert_not_contains "$home_text" "    home-manager"
  assert_contains "$home_text" "neovim"
  assert_contains "$home_text" "jujutsu"
  assert_contains "$home_text" "ripgrep"
  assert_contains "$home_text" "obsidian"
  assert_contains "$home_text" "obsidian-headless"
  assert_contains "$home_text" "    codex"
  assert_contains "$home_text" "    codebase-memory-mcp"
  assert_not_contains "$home_text" "lib.optional (pkgs ? codex)"
  assert_not_contains "$home_text" "lib.optional (pkgs ? codebase-memory-mcp)"
}

test_home_config_manages_obsidian_sync_service() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "systemd.user.services.obsidian-sync"
  assert_contains "$home_text" "pkgs.stdenv.isLinux"
  assert_contains "$home_text" "ob sync-status --path"
  assert_contains "$home_text" "ob sync --path"
  assert_contains "$home_text" 'for vault in "$HOME"/documents/obsidian/*'
  assert_contains "$home_text" "pkgs.obsidian-headless"
  assert_contains "$home_text" "pkgs.nodejs"
  assert_contains "$home_text" "ob not found; run dotfile update"
  assert_contains "$home_text" "No configured Obsidian vault found"
  assert_contains "$home_text" "Restart = \"on-failure\""
  assert_contains "$home_text" "WantedBy = [ \"default.target\" ]"
  assert_not_contains "$home_text" "home.activation.removeLegacyObsidianSyncService"
  assert_not_contains "$home_text" "rm -f \"\$HOME/.config/systemd/user/obsidian-sync.service\""
}

test_home_config_manages_obsidian_settings_in_synced_vault_base() {
  local home_text readme_text agents_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  readme_text="$(<"$REPO_DIR/README.md")"
  agents_text="$(<"$REPO_DIR/AGENTS.md")"

  assert_contains "$home_text" "\"documents/obsidian/Sync/.obsidian/\${name}\""
  assert_not_contains "$home_text" "documents/Sync/.obsidian"
  assert_not_contains "$readme_text" "~/documents/Sync/.obsidian"
  assert_not_contains "$agents_text" "~/documents/Sync/.obsidian"
}

test_home_config_manages_shared_user_tools() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "devTerminalPackages = with pkgs; ["
  assert_contains "$home_text" "standaloneLinuxPackages = with pkgs; ["
  assert_contains "$home_text" "linuxDesktopPackages = with pkgs; ["
  assert_contains "$home_text" "home.packages = devTerminalPackages"
  assert_contains "$home_text" $'    codex\n    codebase-memory-mcp\n    fff-mcp\n    jq'
  assert_contains "$home_text" "\"\${homeDir}/.local/bin\""
  assert_contains "$home_text" "nixosSystem = pkgs.stdenv.isLinux && osConfig != null"
  assert_contains "$home_text" "standaloneLinux = pkgs.stdenv.isLinux && !nixosSystem"
  assert_contains "$home_text" "lib.optionals (!nixosSystem)"
  assert_contains "$home_text" "lib.optionals standaloneLinux"
  assert_contains "$home_text" "lib.optionals pkgs.stdenv.isLinux"
  assert_not_contains "$home_text" "GOPATH"
  assert_not_contains "$home_text" "PNPM_HOME"

  for pkg in ast-grep jq gcc codex codebase-memory-mcp fff-mcp nerd-fonts.fira-code fontconfig openssh waybar ghostty google-chrome obsidian-headless; do
    assert_contains "$home_text" "$pkg"
  done
  for pkg in lua5_1 luarocks tree-sitter unzip; do
    assert_contains "$home_text" "$pkg"
  done
  for setting in \
    "programs.neovim = {" \
    "defaultEditor = true" \
    "vimAlias = true" \
    "viAlias = true" \
    "withPython3 = false" \
    "withRuby = false" \
    "pkgs.vimPlugins.lazy-nvim" \
    "extraPackages = with pkgs; [" \
    "programs.gpg.enable = true" \
    "programs.fd.enable = true" \
    "programs.ripgrep.enable = true" \
    "programs.lazygit.enable = true" \
    "programs.tmux"; do
    assert_contains "$home_text" "$setting"
  done
}

test_nixos_does_not_use_raw_system_packages() {
  local nixos_text
  nixos_text="$(<"$REPO_DIR/config/nixos/configuration.nix")"

  assert_contains "$nixos_text" "fonts.packages = with pkgs; [ nerd-fonts.fira-code ];"
  assert_not_contains "$nixos_text" "environment.systemPackages"
}

test_home_config_uses_tracked_host_username() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "machine = import ./host.nix"
  assert_contains "$home_text" "home.username = machine.username"
  assert_contains "$home_text" "\"/home/\${machine.username}\""
  assert_not_contains "$home_text" 'home.username = "quando"'
  assert_not_contains "$home_text" '"/home/quando"'
}

test_zsh_completion_cache_uses_glob_qualifiers() {
  local home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home_text" "setopt local_options extended_glob"
  assert_contains "$home_text" "compinit -C -d"
}

test_home_config_manages_gitconfig_and_starship_config() {
  local home_text zsh_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$home_text" "forceSource = source:"
  assert_contains "$home_text" "programs.git = {"
  assert_contains "$home_text" "settings = {"
  assert_contains "$home_text" "name = \"Quan Do\""
  assert_contains "$home_text" "email = \"minhquand3@gmail.com\""
  assert_contains "$home_text" "ignorecase = false"
  assert_not_contains "$home_text" "editor = \"nvim\""
  assert_contains "$home_text" "commit.gpgsign = true"
  assert_contains "$home_text" "tag.gpgsign = true"
  assert_contains "$home_text" "gpg.program = \"gpg\""
  assert_contains "$home_text" "path = \"~/.gitconfig.local\""
  assert_not_contains "$home_text" "path = \"~/.gitconfig.windows\""
  assert_not_contains "$home_text" "home.file.\".gitconfig\""
  assert_not_contains "$home_text" "forceSource ./shared/.gitconfig"
  assert_contains "$home_text" "force = true"
  assert_contains "$home_text" "programs.starship = {"
  assert_contains "$home_text" "enable = true"
  assert_contains "$home_text" "settings = builtins.fromTOML"
  assert_contains "$home_text" "builtins.readFile ./shared/config/starship.toml"
  assert_not_contains "$home_text" "xdg.configFile.\"starship.toml\""
  assert_not_contains "$zsh_text" "starship init zsh"
}

test_home_config_owns_remaining_dotfiles() {
  local home_text codex_merge_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  if [[ -f "$REPO_DIR/scripts/codex_seed_merge.py" ]]; then
    codex_merge_text="$(<"$REPO_DIR/scripts/codex_seed_merge.py")"
  else
    codex_merge_text=""
  fi

  assert_not_contains "$home_text" "home.file.\".vimrc\""
  assert_not_contains "$home_text" "forceSource ./shared/.vimrc"
  assert_not_contains "$home_text" "home.file.\".tmux.conf\""
  assert_not_contains "$home_text" "home.file.\".zprofile\""
  assert_not_contains "$home_text" "forceSource ./unix/.zprofile"
  assert_not_contains "$home_text" "home.file.\".zshrc.base\""
  assert_not_contains "$home_text" "forceSource ./unix/.zshrc.base"
  assert_not_contains "$home_text" "home.file.\".zshrc\""
  assert_contains "$home_text" "initContent = lib.mkOrder 550 (builtins.readFile ./unix/.zshrc.base)"
  assert_not_contains "$home_text" "source \"\$HOME/.zshrc.base\""
  assert_contains "$home_text" "\".ssh/config\" = forceSource ./shared/.ssh/config"
  assert_contains "$home_text" "forceSource ./shared/.ssh/config"
  assert_contains "$home_text" "\".claude/settings.json\" = forceSource ./shared/ai/claude/settings.json"
  assert_contains "$home_text" "forceSource ./shared/ai/claude/settings.json"
  assert_contains "$home_text" "forceSource ./shared/ai/AGENTS.md"
  assert_not_contains "$home_text" "home.file.\".codex/config.toml\""
  assert_contains "$home_text" "home.activation.seedCodexConfig"
  assert_contains "$home_text" "\${../scripts/codex_seed_merge.py}"
  assert_not_contains "$home_text" "import tomllib"
  assert_contains "$codex_merge_text" "Codex live config has settings missing from the tracked seed"
  assert_contains "$home_text" "cp \"\$source\" \"\$target\""
  assert_contains "$home_text" "cavemanSrc = pkgs.fetchFromGitHub"
  assert_contains "$home_text" "owner = \"JuliusBrussee\""
  assert_contains "$home_text" "repo = \"caveman\""
  assert_contains "$home_text" "\".agents/skills/caveman/SKILL.md\" = forceSource \"\${cavemanSrc}/skills/caveman/SKILL.md\""
  assert_not_contains "$home_text" ".codex/skills/caveman"
  assert_contains "$home_text" "superpowersSrc = pkgs.fetchFromGitHub"
  assert_contains "$home_text" "owner = \"obra\""
  assert_contains "$home_text" "repo = \"superpowers\""
  assert_contains "$home_text" "\".agents/skills/systematic-debugging\" = forceSource \"\${superpowersSrc}/skills/systematic-debugging\""
  assert_contains "$home_text" "\".agents/skills/test-driven-development\" = forceSource \"\${superpowersSrc}/skills/test-driven-development\""
  assert_contains "$home_text" "\".agents/skills/verification-before-completion\" = forceSource \"\${superpowersSrc}/skills/verification-before-completion\""
  assert_not_contains "$home_text" ".agents/skills/brainstorming"
  assert_not_contains "$home_text" ".codex/skills/"
  assert_contains "$home_text" "obsidianSettings = ["
  assert_contains "$home_text" "\"app.json\""
  assert_contains "$home_text" "obsidianFiles = lib.genAttrs"
  assert_not_contains "$home_text" "builtins.listToAttrs (map"
  assert_contains "$home_text" "\"documents/obsidian/Sync/.obsidian/\${name}\""
  assert_contains "$home_text" "\"plugins/calendar/data.json\""
  assert_contains "$home_text" "forceSource (./shared/obsidian + \"/\${lib.removePrefix \"documents/obsidian/Sync/.obsidian/\" path}\")"
  assert_contains "$home_text" "\".local/bin/dotfile\" = {"
  assert_not_contains "$home_text" "\".local/bin/dotfile\" = lib.mkIf pkgs.stdenv.isLinux"
  assert_contains "$home_text" "dotfiles_dir=\"''\${DOTFILES_DIR:-\$HOME/dotfiles}\""
  assert_contains "$home_text" 'exec "$dotfiles_dir/dotfile" "$@"'
  assert_not_contains "$home_text" "\".zshrc.mac\""
  assert_not_contains "$home_text" "forceSource ./mac/.zshrc.mac"
  assert_contains "$home_text" "\".local/bin/caf\" = lib.mkIf pkgs.stdenv.isDarwin"
  assert_contains "$home_text" "forceSource ./mac/bin/caf"
  assert_contains "$home_text" "pkgs.stdenv.isDarwin"
}

test_codex_seed_merge_engine_applies_live_only_nested_toml() {
  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$tmp/codex_seed_merge.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  script="$REPO_DIR/scripts/codex_seed_merge.py"
  assert_file_exists "$script"

  cat > "$live" <<'EOF'
model = "gpt-5.5"
approval_policy = "on-request"

[features]
memories = true
multi_agent = true

[projects."/home/quando/dotfiles"]
trust_level = "trusted"

[hooks]
SessionStart = [{ matcher = "startup", hooks = [{ type = "command", command = "echo hi" }] }]
EOF

  cat > "$seed" <<'EOF'
model = "gpt-5.5"

[features]
memories = true
EOF

  output="$(python3 "$script" "$live" "$seed" "$seed")"

  assert_contains "$output" "Applied Codex live config additions to tracked seed"
  assert_contains "$(<"$seed")" 'approval_policy = "on-request"'
  assert_contains "$(<"$seed")" '[features]'
  assert_contains "$(<"$seed")" "multi_agent = true"
  assert_contains "$(<"$seed")" '[projects."/home/quando/dotfiles"]'
  assert_contains "$(<"$seed")" 'trust_level = "trusted"'
  assert_not_contains "$(<"$seed")" '[hooks]'
  assert_not_contains "$(<"$seed")" 'SessionStart'
  assert_not_contains "$(<"$seed")" 'command = "echo hi"'
  assert_exit_code 0 python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$seed"
  rm -rf "$tmp"
}

test_pi_codex_status_formats_plan_usage_and_resets() {
  local extension output
  extension="$REPO_DIR/config/shared/ai/pi/codex-status.js"
  assert_file_exists "$extension"

  output="$(node --input-type=module - "$extension" <<'EOF'
const { default: factory, formatUsage } = await import(process.argv[2]);
if (typeof factory !== "function") throw new Error(`default export is ${typeof factory}`);
console.log(formatUsage({
  plan_type: "prolite",
  rate_limit: {
    allowed: true,
    limit_reached: false,
    primary_window: { used_percent: 25, reset_after_seconds: 14156 },
    secondary_window: { used_percent: 7, reset_after_seconds: 582213 }
  },
  credits: { has_credits: false, balance: "0" },
  rate_limit_reset_credits: { available_count: 4 }
}));
EOF
)"

  assert_contains "$output" "Plan: Pro Lite"
  assert_contains "$output" "5-hour limit: 25% used, resets in 3h 56m"
  assert_contains "$output" "Weekly limit: 7% used, resets in 6d 17h"
  assert_contains "$output" "Reset tokens: 4"
  assert_contains "$output" 'Credits: $0'
}

test_pi_seed_merge_engine_applies_live_only_nested_json() {
  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/pi_seed_merge.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"

  assert_file_exists "$script"

  cat > "$live" <<'EOF'
{
  "defaultModel": "live-model",
  "packages": ["runtime-package"],
  "custom": {"enabled": true},
  "mcpServers": {"local": {"command": "local-mcp"}}
}
EOF
  cat > "$seed" <<'EOF'
{
  "defaultModel": "tracked-model",
  "packages": ["tracked-package"],
  "mcpServers": {}
}
EOF

  output="$(python3 "$script" "$live" "$seed" "$seed")"

  assert_contains "$output" "Applied Pi live config additions to tracked seed"
  assert_equals "live-model" "$(jq -r '.defaultModel' "$seed")"
  assert_equals "tracked-package" "$(jq -r '.packages[]' "$seed")"
  assert_equals "true" "$(jq -r '.custom.enabled' "$seed")"
  assert_equals "local-mcp" "$(jq -r '.mcpServers.local.command' "$seed")"
  assert_exit_code 0 jq empty "$seed"
  rm -rf "$tmp"
}

test_claude_settings_do_not_track_machine_cache_paths() {
  local claude_text
  claude_text="$(<"$REPO_DIR/config/shared/ai/claude/settings.json")"

  assert_not_contains "$claude_text" "/home/quando"
  assert_not_contains "$claude_text" "/Users/quando"
  assert_not_contains "$claude_text" "plugins/cache"
}

test_darwin_config_manages_core_packages() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_contains "$darwin_text" "nix.settings.experimental-features"
  assert_not_contains "$darwin_text" "nixpkgs.config.allowUnfree"
  assert_contains "$darwin_text" "programs.zsh.enable = true"
  assert_contains "$darwin_text" "system.primaryUser = machine.username"
}

test_darwin_does_not_use_raw_system_packages() {
  local darwin_text
  darwin_text="$(<"$REPO_DIR/config/darwin.nix")"

  assert_not_contains "$darwin_text" "environment.systemPackages"
}

test_home_config_uses_home_manager_zsh_plugins() {
  local home_text zsh_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$home_text" "programs.zsh = {"
  assert_contains "$home_text" "enable = true"
  assert_not_contains "$home_text" "brew shellenv"
  assert_not_contains "$home_text" "/opt/homebrew/bin/brew"
  assert_not_contains "$home_text" "/usr/local/bin/brew"
  assert_contains "$home_text" "enableCompletion = true"
  assert_contains "$home_text" "completionInit = ''"
  assert_contains "$home_text" "_zcompdump="
  assert_contains "$home_text" "compinit -d \"\$_zcompdump\""
  assert_contains "$home_text" "compinit -C -d \"\$_zcompdump\""
  assert_contains "$home_text" "zstyle ':completion:*' matcher-list"
  assert_contains "$home_text" "defaultKeymap = \"viins\""
  assert_contains "$home_text" "history = {"
  assert_contains "$home_text" "size = 50000"
  assert_contains "$home_text" "save = 10000"
  assert_contains "$home_text" "setOptions = [ \"INC_APPEND_HISTORY\" \"HIST_VERIFY\" ]"
  assert_contains "$home_text" "autosuggestion.enable = true"
  assert_contains "$home_text" "fastSyntaxHighlighting.enable = true"
  assert_contains "$home_text" "plugins = ["
  assert_contains "$home_text" "pkgs.zsh-fzf-tab"
  assert_not_contains "$home_text" "xdg.dataFile.\"zsh/plugins"
  assert_not_contains "$zsh_text" "export SHELL="
  assert_not_contains "$zsh_text" "export EDITOR=nvim"
  assert_not_contains "$zsh_text" "alias vim=nvim"
  assert_not_contains "$zsh_text" "/opt/nvim-linux-x86_64"
  assert_not_contains "$zsh_text" "HYPRSHOT_DIR"
  assert_not_contains "$zsh_text" "hyprshot"
  assert_not_contains "$zsh_text" "GOPATH"
  assert_not_contains "$zsh_text" "GOBIN"
  assert_not_contains "$zsh_text" "PNPM_HOME"
  assert_not_contains "$zsh_text" "\$HOME/.local/bin"
  assert_not_contains "$zsh_text" ".opencode/bin"
  assert_not_contains "$zsh_text" ".bun/bin"
  assert_not_contains "$zsh_text" "/snap/bin"
  assert_not_contains "$zsh_text" ".devcontainers/bin"
  assert_not_contains "$zsh_text" "LESS_TERMCAP"
  assert_not_contains "$zsh_text" "_zsh_plugins="
  assert_not_contains "$zsh_text" "zsh-autosuggestions.zsh"
  assert_not_contains "$zsh_text" "fast-syntax-highlighting.plugin.zsh"
  assert_not_contains "$zsh_text" "fzf-tab.plugin.zsh"
  assert_not_contains "$zsh_text" "HISTFILE="
  assert_not_contains "$zsh_text" "HISTSIZE="
  assert_not_contains "$zsh_text" "SAVEHIST="
  assert_not_contains "$zsh_text" "setopt append_history"
  assert_not_contains "$zsh_text" "bindkey -v"
  assert_not_contains "$zsh_text" "autoload -Uz compinit"
  assert_not_contains "$zsh_text" "_zcompdump="
  assert_not_contains "$zsh_text" "compinit -d"
  assert_not_contains "$zsh_text" "compinit -C"
  assert_not_contains "$zsh_text" "zstyle ':completion:*' matcher-list"
  assert_not_contains "$zsh_text" ".zshrc.mac"
  assert_contains "$home_text" "programs.zoxide = {"
  assert_contains "$home_text" "enableZshIntegration = true"
  assert_contains "$home_text" "options = [ \"--cmd\" \"cd\" ]"
  assert_not_contains "$zsh_text" "zoxide init zsh"
  assert_not_contains "$zsh_text" "_ZO_DOCTOR"
  assert_contains "$home_text" "programs.fzf = {"
  assert_contains "$home_text" "enableZshIntegration = true"
  assert_not_contains "$zsh_text" "fzf --zsh"
  assert_contains "$home_text" "programs.jujutsu = {"
  assert_contains "$home_text" "settings = builtins.fromTOML"
  assert_contains "$home_text" "builtins.readFile ./shared/config/jj/config.toml"
  assert_not_contains "$zsh_text" "COMPLETE=zsh jj"
}

test_zsh_arrow_keys_search_history_by_prefix() {
  local zsh_text
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_contains "$zsh_text" "bindkey -M viins '^[[A' history-beginning-search-backward"
  assert_contains "$zsh_text" "bindkey -M viins '^[[B' history-beginning-search-forward"
  assert_contains "$zsh_text" "bindkey -M viins '^[OA' history-beginning-search-backward"
  assert_contains "$zsh_text" "bindkey -M viins '^[OB' history-beginning-search-forward"
}

test_zsh_keytimeout_allows_bracketed_paste_sequences() {
  local zsh_text
  zsh_text="$(<"$REPO_DIR/config/unix/.zshrc.base")"

  assert_not_contains "$zsh_text" $'\nexport KEYTIMEOUT=1\n'
  assert_contains "$zsh_text" $'\nexport KEYTIMEOUT=10\n'
}

test_tmux_enables_synchronized_output() {
local tmux_text
tmux_text="$(<"$REPO_DIR/config/unix/.tmux.conf")"

assert_contains "$tmux_text" 'terminal-features ",*:sync"'
}

test_home_config_uses_home_manager_tmux_plugins() {
  local home_text tmux_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  tmux_text="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_contains "$home_text" "programs.tmux = {"
  assert_contains "$home_text" "enable = true"
  assert_contains "$home_text" "plugins = ["
  assert_contains "$home_text" "pkgs.tmuxPlugins.yank"
  assert_contains "$home_text" "pkgs.tmuxPlugins.catppuccin"
  assert_contains "$home_text" "extraConfig = builtins.readFile ./unix/.tmux.conf"
  assert_not_contains "$home_text" "home.file.\".tmux/plugins"
  assert_not_contains "$tmux_text" "run ~/.tmux/plugins"
}

test_home_config_owns_existing_xdg_configs() {
  local home_text lazy_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  lazy_text="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/lazy.lua")"

  assert_not_contains "$home_text" "xdg.configFile.\"jj\""
  assert_not_contains "$home_text" "xdg.configFile.\"nvim\""
  assert_contains "$home_text" "initLua = builtins.readFile ./shared/config/nvim/init.lua"
  assert_contains "$home_text" "home.activation.migrateNvimConfig"
  assert_contains "$home_text" 'entryBefore [ "checkLinkTargets" ]'
  assert_contains "$home_text" 'rm -f "$nvim_config"'
  assert_contains "$home_text" "xdg.configFile.\"nvim/init.lua\".force = true"
  assert_contains "$home_text" "xdg.configFile.\"nvim/lua\" = forceSource ./shared/config/nvim/lua"
  assert_not_contains "$home_text" "xdg.configFile.\"nvim/lazy-lock.json\""
  assert_not_contains "$(<"$REPO_DIR/config/shared/config/nvim/init.lua")" "bootstrap lazy.nvim"
  assert_not_contains "$lazy_text" "lazyrepo"
  assert_not_contains "$lazy_text" "git\", \"clone"
  assert_not_contains "$lazy_text" "enabled = true, -- check for plugin updates"
  assert_not_contains "$lazy_text" "latest git commit"
  assert_contains "$lazy_text" "run dotfile update"
  assert_contains "$home_text" "linuxConfig = source: lib.mkIf pkgs.stdenv.isLinux (forceSource source)"
  assert_contains "$home_text" "xdg.configFile.\"fcitx5\""
  assert_contains "$home_text" "./unix/config/fcitx5"
  assert_contains "$home_text" "xdg.configFile.\"ghostty/config\""
  assert_contains "$home_text" "./unix/config/ghostty/config"
  assert_contains "$home_text" "xdg.configFile.\"hypr\""
  assert_contains "$home_text" "./unix/config/hypr"
  assert_contains "$home_text" "xdg.configFile.\"waybar\""
  assert_contains "$home_text" "./unix/config/waybar"
  assert_contains "$home_text" "force = true"
}

test_waybar_cpu_does_not_poll_every_second() {
  local waybar_text
  waybar_text="$(<"$REPO_DIR/config/unix/config/waybar/config.jsonc")"

  assert_contains "$waybar_text" '"cpu": {'
  assert_contains "$waybar_text" '"interval": 5'
}

test_doctor_paths_cover_home_manager_managed_paths() {
  local doctor_text home_text
  home_text="$(<"$REPO_DIR/config/home.nix")"
  doctor_text="$(<"$REPO_DIR/scripts/doctor.sh")"
  if [[ -e "$REPO_DIR/config/home-manager-managed-paths" ]]; then
    echo "  FAILED: Home Manager paths should be declared only in config/home.nix" >> "$ERROR_FILE"
  fi
  assert_not_contains "$doctor_text" "home-manager-managed-paths"
  assert_not_contains "$doctor_text" "_read_home_manager_managed_paths()"
  assert_not_contains "$doctor_text" "  .gitconfig"
  assert_not_contains "$doctor_text" "  .vimrc"
  assert_not_contains "$doctor_text" "  .zprofile"
  assert_not_contains "$doctor_text" "  .zshrc.base"
  assert_not_contains "$doctor_text" "REQUIRED_SYMLINKS"
  assert_not_contains "$doctor_text" "_doctor_check_managed_paths"
  assert_not_contains "$home_text" 'home.file.".codex/config.toml"'
}
