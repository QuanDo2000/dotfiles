# Exercise the actual flake profile and native HM extendModules boundary.
{ flake, machine }:
let
  profile = flake.homeConfigurations."${machine.username}@linux";
  basePkgs = profile.pkgs;
  customPkgs = basePkgs // {
    jq = basePkgs.jq.overrideAttrs (_: { pname = "home-pkgs-argument-witness"; });
  };
  cases = {
    unfree = { nixpkgs.config.allowUnfree = false; };
    overlay = { nixpkgs.overlays = [ (_final: prev: {
      jq = prev.jq.overrideAttrs (_: { pname = "home-pkgs-overlay-witness"; });
    }) ]; };
    pkgsArgument = { lib, ... }: { _module.args.pkgs = lib.mkForce customPkgs; };
    unusedPredicate = { nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = throw "unused Home package predicate was forced";
    }; };
  };
in
builtins.mapAttrs (_: extra:
  let cfg = profile.extendModules { modules = [ extra ]; };
  in {
    allowUnfree = cfg.pkgs.config.allowUnfree;
    jqName = cfg.pkgs.jq.pname;
  }
) cases
