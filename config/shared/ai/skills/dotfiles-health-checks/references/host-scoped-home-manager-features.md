# Host-scoped Home Manager features

Use this pattern when one machine needs a package, generated file, or user unit that other machines sharing `home.nix` must not receive.

## Failure mode

`pkgs.stdenv.isLinux` is platform-scoped, not host-scoped. Putting a server-only package in a shared Linux package list and guarding its units with `lib.mkIf pkgs.stdenv.isLinux` enables it for every Linux Home Manager target, including generic Linux and NixOS configurations.

## Minimal explicit profile pattern

1. Add one boolean module argument, defaulting to disabled:

```nix
{ pkgs, lib, featureEnabled ? false, ... }:
```

2. Gate the package, generated files, services, and timers with the same boolean:

```nix
home.packages = commonPackages
  ++ lib.optionals featureEnabled [ pkgs.example ];

xdg.configFile."example/config" = lib.mkIf featureEnabled {
  text = ''...'';
};

systemd.user.services.example = lib.mkIf featureEnabled { ... };
systemd.user.timers.example = lib.mkIf featureEnabled { ... };
```

Gate the whole `xdg.configFile` attrset. Using `.text = lib.mkIf false ...` can leave an option node whose required `source` has no value, causing the disabled profile to fail evaluation.

3. Keep the generic target explicitly disabled and add one named machine-role target:

```nix
homeConfigurations."${machine.username}@linux" = home-manager.lib.homeManagerConfiguration {
  pkgs = linuxPkgs;
  extraSpecialArgs.featureEnabled = false;
  modules = [ ./config/home.nix ];
};

homeConfigurations."${machine.username}@server" = home-manager.lib.homeManagerConfiguration {
  pkgs = linuxPkgs;
  extraSpecialArgs.featureEnabled = true;
  modules = [ ./config/home.nix ];
};
```

When `home.nix` is imported through NixOS or nix-darwin, also pass `featureEnabled = false` through `home-manager.extraSpecialArgs`. Home Manager may still request declared module arguments instead of honoring a function default when no special argument is provided.

4. Route each platform installer/update command to the intended profile. Keep generic Linux on `@linux`; route only the server workflow to `@server`.

5. Update the doctor/health check to evaluate the same profile the platform updater activates. A doctor that evaluates the generic target while the server runs the dedicated target can miss server-only breakage.

## Smallest useful checks

Start with a failing regression check, then verify both sides:

```bash
# Enabled target builds and contains the service/package.
nix build '.#homeConfigurations."USER@server".activationPackage' --no-link
nix eval --json '.#homeConfigurations."USER@server".config.systemd.user.services' \
  | jq -r 'has("example")'

# Disabled target also builds and omits the service/package.
nix build '.#homeConfigurations."USER@linux".activationPackage' --no-link
nix eval --json '.#homeConfigurations."USER@linux".config.systemd.user.services' \
  | jq -r 'has("example")'
```

Also test that platform install/update helpers choose the correct flake target and that the doctor evaluates it. Finish with repository-native checks and an activated-state service check on the intended host.

## Fail closed on data sources

A mount-point condition only proves that the parent filesystem is mounted. It does not prove that every backup source exists. Many backup tools will still create a valid but incomplete snapshot when one source is absent; retention may later prune older complete snapshots.

For a data-bearing systemd unit, require both the mount and every expected source:

```nix
Unit = {
  ConditionPathIsMountPoint = "/mnt/storage";
  ConditionPathIsDirectory = [
    "/mnt/storage/Storage/Documents"
    "/mnt/storage/Storage/Book"
    "/mnt/storage/Storage/Music"
  ];
};
```

Verify the generated unit, not just source text:

```bash
nix eval --json '.#homeConfigurations."USER@server".config.systemd.user.services.example.Unit.ConditionPathIsDirectory'
systemctl --user cat example.service
```

Treat these conditions as data-loss prevention, not optional hardening. Keep a small regression assertion for every required source directory.
