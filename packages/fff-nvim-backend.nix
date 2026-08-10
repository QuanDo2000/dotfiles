{ fetchurl, stdenv }:

let
  asset = {
    x86_64-linux = {
      name = "x86_64-unknown-linux-gnu.so";
      hash = "sha256-0z1mxosSn/yc3X61QRv+II+FCD+7EKKf3G0puHWk+3w=";
    };
    aarch64-darwin = {
      name = "aarch64-apple-darwin.dylib";
      hash = "sha256-oCz40aOIb0qjWD602sNHRb2lmiuFfMqnO/oesoFLGaU=";
    };
  }.${stdenv.hostPlatform.system} or (throw "Unsupported fff.nvim platform: ${stdenv.hostPlatform.system}");
in
fetchurl {
  url = "https://github.com/dmtrKovalenko/fff/releases/download/v0.10.1/${asset.name}";
  inherit (asset) hash name;
}
