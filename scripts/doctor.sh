#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

if ! declare -F host_config_value >/dev/null; then
  # shellcheck source=scripts/host_config.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host_config.sh"
fi

_physical_path() {
  local path="$1" parent
  parent="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || { printf '%s\n' "$path"; return; }
  printf '%s/%s\n' "$parent" "$(basename "$path")"
}

# Helper: check that a file is a symlink pointing into DOTFILES_DIR.
_check_symlink() {
  local name="$1" platform="${2:-$(detect_platform)}" exact_target="${3:-}"
  local target="$HOME/$name" expected="$DOTFILES_DIR/... or Home Manager store target"
  if [ -L "$target" ]; then
    local link_target physical_link_target physical_dotfiles physical_exact=""
    link_target="$(resolve_symlink "$target")"
    physical_link_target="$(_physical_path "$link_target")"
    physical_dotfiles="$(cd -P "$DOTFILES_DIR" 2>/dev/null && pwd)" || physical_dotfiles="$DOTFILES_DIR"
    if [[ -n "$exact_target" ]]; then
      expected="$exact_target or Home Manager store target"
      physical_exact="$(_physical_path "$exact_target")"
    fi
    if [[ -e "$target" ]] && { { [[ -n "$physical_exact" ]] && [[ "$physical_link_target" == "$physical_exact" ]]; } \
      || { [[ -z "$physical_exact" ]] && [[ "$physical_link_target" == "$physical_dotfiles/"* ]]; } \
      || { is_home_manager_platform "$platform" && [[ "$link_target" == /nix/store/* ]]; }; }; then
      success "$name -> $link_target"
    else
      fail_soft "$name points to $link_target (expected $expected)"
      errors=$((errors + 1))
    fi
  elif [ -e "$target" ]; then
    fail_soft "$name exists but is not a symlink"
    errors=$((errors + 1))
  else
    fail_soft "$name not found"
    errors=$((errors + 1))
  fi
}

_check_writable_file() {
  local name="$1" target="$HOME/$1"
  if [[ -f "$target" && -w "$target" ]]; then
    success "$name writable"
  else
    fail_soft "$name missing or not writable"
    errors=$((errors + 1))
  fi
}

_check_neovim_runtime() {
  if [[ "${DOTFILE_DOCTOR_SKIP_NEOVIM_RUNTIME:-false}" == "true" ]]; then
    info "Skipping Neovim runtime verification: DOTFILE_DOCTOR_SKIP_NEOVIM_RUNTIME=true"
    return 0
  fi
  local tracked="$DOTFILES_DIR/config/shared/config/nvim" runtime="$HOME/.config/nvim"
  [[ -f "$tracked/init.lua" && -f "$tracked/lazy-lock.json" ]] || return 0

  local before="$errors" provider_prelude
  provider_prelude='vim.g.loaded_node_provider=0;vim.g.loaded_perl_provider=0;vim.g.loaded_ruby_provider=0;vim.g.loaded_python3_provider=0'
  if [[ ! -f "$runtime/init.lua" ]] \
    || { ! cmp -s "$tracked/init.lua" "$runtime/init.lua" \
      && { [[ "$(head -n 1 "$runtime/init.lua" 2>/dev/null)" != "$provider_prelude" ]] \
        || ! tail -n +2 "$runtime/init.lua" | cmp -s "$tracked/init.lua" -; }; }; then
    fail_soft "Neovim config differs from tracked generated config"
    errors=$((errors + 1))
  fi

  if [[ ! -d "$runtime/lua" ]] || ! diff -qr "$tracked/lua/" "$runtime/lua/" >/dev/null 2>&1; then
    fail_soft "Neovim Lua config differs from tracked generated config"
    errors=$((errors + 1))
  fi

  local tracked_lock runtime_lock
  tracked_lock="$(jq -cS . "$tracked/lazy-lock.json" 2>/dev/null || true)"
  runtime_lock="$(jq -cS . "$runtime/lazy-lock.json" 2>/dev/null || true)"
  if [[ -z "$tracked_lock" || "$runtime_lock" != "$tracked_lock" ]]; then
    fail_soft "Neovim lock differs from tracked lock"
    errors=$((errors + 1))
  fi

  local name expected plugin actual
  while IFS=$'\t' read -r name expected; do
    [[ "$name" == lazy.nvim ]] && continue
    plugin="$HOME/.local/share/nvim/lazy/$name"
    actual="$(git -C "$plugin" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$actual" != "$expected" ]]; then
      fail_soft "$name commit differs from tracked lock"
      errors=$((errors + 1))
    elif [[ -n "$(git -C "$plugin" status --porcelain --untracked-files=all 2>/dev/null | grep -vFx '?? doc/tags')" ]]; then
      fail_soft "$name worktree differs from tracked checkout"
      errors=$((errors + 1))
    fi
  done < <(jq -r 'to_entries[] | [.key, .value.commit] | @tsv' "$tracked/lazy-lock.json" 2>/dev/null)

  [[ "$errors" != "$before" ]] || success "Neovim config, lock, and plugin commits match"
}

_check_managed_commands() {
  local command_name command_path nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  for command_name in nvim codex pi codebase-memory-mcp; do
    command_path="$(command -v "$command_name" 2>/dev/null || true)"
    if [[ "$command_name" == pi && "$command_path" == "$nvm_dir"/versions/node/* ]]; then
      fail_soft "pi is shadowed by NVM at $command_path; uninstall the npm-global Pi and restart the shell"
      errors=$((errors + 1))
    elif [[ -n "$command_path" ]]; then
      success "$command_name available"
    else
      fail_soft "$command_name not found"
      errors=$((errors + 1))
    fi
  done
}

_is_obsidian_service_target() {
  [[ "$1" =~ ^/nix/store/[^/]+-obsidian-sync\.service/obsidian-sync\.service$ ]]
}

_check_obsidian_service() {
  local platform="${1:-$(detect_platform)}" marker="$HOME/.config/dotfiles/profile"
  local expected=""
  if [[ -f "$marker" ]]; then
    local marker_values marker_count
    marker_values="$(sed -n 's/^obsidianSync=\(true\|false\)$/\1/p' "$marker")"
    marker_count="$(grep -Ec '^obsidianSync=(true|false)$' "$marker" || true)"
    if [[ "$marker_count" -ne 1 ]]; then
      fail_soft "invalid dotfiles profile marker: expected one obsidianSync=true|false line"
      errors=$((errors + 1))
      return 0
    fi
    expected="$marker_values"
  else
    case "$platform" in
      nixos|arch) expected=true ;;
      *) expected=false ;;
    esac
  fi
  [[ "$DRY" == true || "$expected" != true ]] && return 0
  local target="$HOME/.config/systemd/user/obsidian-sync.service" link_target=""
  if [[ -L "$target" && -e "$target" ]]; then
    link_target="$(readlink -f "$target" 2>/dev/null || true)"
  fi
  if _is_obsidian_service_target "$link_target"; then
    success "obsidian-sync.service installed"
  else
    fail_soft "obsidian-sync.service not installed"
    errors=$((errors + 1))
  fi
}

_check_nix_eval() {
  local label="$1"
  local target="$2"
  local output

  if output="$(nix eval --raw "$target" 2>&1 >/dev/null)"; then
    success "$label evaluates"
  else
    if [[ "$output" == *"fetcher-cache-v4.sqlite"* ]]; then
      local cache_dir
      cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfile-nix-cache.XXXXXX")"
      if output="$(XDG_CACHE_HOME="$cache_dir" nix eval --raw "$target" 2>&1 >/dev/null)"; then
        rm -rf "$cache_dir"
        success "$label evaluates"
        return
      fi
      rm -rf "$cache_dir"
    fi

    output="${output//$'\n'/ }"
    if [[ -n "$output" ]]; then
      fail_soft "$label failed to evaluate: $output"
    else
      fail_soft "$label failed to evaluate"
    fi
    errors=$((errors + 1))
  fi
}

_check_release_transaction() {
  local label="$1" transaction_dir="$2" package_file="$3" lock_file="$4" output
  _release_transaction_pending "$transaction_dir" || return 0
  if [[ "$DRY" == "true" ]]; then
    fail_soft "Interrupted $label update needs recovery"
    errors=$((errors + 1))
    return
  fi
  if output="$(
    (
      trap '_release_release_transaction "$transaction_dir"' EXIT
      _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "$label"
    ) 2>&1
  )"; then
    success "Recovered interrupted $label update"
  else
    output="${output//$'\n'/ }"
    fail_soft "Failed to recover interrupted $label update: $output"
    errors=$((errors + 1))
  fi
}

_check_release_transactions() {
  _check_release_transaction \
    "Pi package" \
    "$DOTFILES_DIR/packages/.pi-update.transaction" \
    "$DOTFILES_DIR/packages/pi-agent.nix" \
    "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  _check_release_transaction \
    "Obsidian Headless package" \
    "$DOTFILES_DIR/packages/.obsidian-update.transaction" \
    "$DOTFILES_DIR/packages/obsidian-headless.nix" \
    "$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"
}

_check_nix_config() {
  local platform="$1"
  is_home_manager_platform "$platform" || return 0

  if [[ "${DOTFILE_DOCTOR_SKIP_NIX_EVAL:-false}" == "true" ]]; then
    info "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true"
    return 0
  fi
  if [[ "$DRY" == "true" ]]; then
    info "Skipping Nix evaluation in dry-run mode"
    return 0
  fi
  if ! command -v nix >/dev/null 2>&1; then
    info "Skipping Nix evaluation: nix not found"
    return 0
  fi
  if [[ ! -f "$DOTFILES_DIR/flake.nix" ]]; then
    info "Skipping Nix evaluation: flake.nix not found"
    return 0
  fi

  case "$platform" in
    nixos)
      local host_name
      host_name="$(host_config_value hostName 2>/dev/null || true)"
      if [[ -z "$host_name" ]]; then
        fail_soft "NixOS hostName failed to evaluate"
        errors=$((errors + 1))
        return
      fi
      is_wsl && host_name="${host_name}-wsl"
      _check_nix_eval "NixOS configuration $host_name" "$DOTFILES_DIR#nixosConfigurations.$host_name.config.system.build.toplevel.drvPath"
      ;;
    mac)
      _check_nix_eval "nix-darwin configuration mac" "$DOTFILES_DIR#darwinConfigurations.mac.config.system.build.toplevel.drvPath"
      ;;
    arch | debian)
      local username
      username="$(host_config_value username 2>/dev/null || true)"
      if [[ -z "$username" ]]; then
        fail_soft "Home Manager username failed to evaluate"
        errors=$((errors + 1))
        return
      fi
      local profile=linux
      [[ "$platform" == arch ]] && profile=arch-server
      _check_nix_eval "Home Manager configuration $username@$profile" "$DOTFILES_DIR#homeConfigurations.\"$username@$profile\".activationPackage.drvPath"
      ;;
  esac
}

function doctor {
  local errors=0
  local platform
  platform="$(detect_platform)"

  _check_release_transactions
  info "Verifying symlinks..."
  _check_symlink .zshrc "$platform"
  _check_symlink .config/tmux/tmux.conf "$platform"
  _check_symlink .config/git/config "$platform"
  _check_symlink .config/nvim/init.lua "$platform"
  _check_neovim_runtime
  _check_symlink .local/bin/dotfile "$platform" "$DOTFILES_DIR/dotfile"
  _check_writable_file .codex/config.toml
  _check_writable_file .pi/agent/settings.json
  _check_writable_file .pi/agent/mcp.json
  _check_managed_commands
  _check_obsidian_service "$platform"
  _check_nix_config "$platform"

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
    return 0
  fi

  info "$errors issue(s) found" --force
  return 1
}
