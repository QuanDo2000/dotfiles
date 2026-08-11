{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  pins = builtins.fromJSON (builtins.readFile ./fff-release.json);
  platform = stdenvNoCC.hostPlatform.system;
  source = pins.mcp.${platform} or (throw "Unsupported FFF MCP platform: ${platform}");
in
stdenvNoCC.mkDerivation {
  pname = "fff-mcp";
  version = pins.version;

  src = fetchurl {
    url = "https://github.com/dmtrKovalenko/fff/releases/download/v${pins.version}/${source.file}";
    inherit (source) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/fff-mcp"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast file search MCP server";
    homepage = "https://github.com/dmtrKovalenko/fff";
    license = licenses.mit;
    mainProgram = "fff-mcp";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
