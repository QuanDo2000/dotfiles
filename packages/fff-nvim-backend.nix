{ fetchurl, stdenv }:

let
  pins = builtins.fromJSON (builtins.readFile ./fff-release.json);
  asset = pins.backend.${stdenv.hostPlatform.system}
    or (throw "Unsupported fff.nvim platform: ${stdenv.hostPlatform.system}");
in
fetchurl {
  url = "https://github.com/dmtrKovalenko/fff/releases/download/v${pins.version}/${asset.file}";
  inherit (asset) hash;
  name = asset.file;
}
