{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.9.6";
  platform = stdenvNoCC.hostPlatform.system;
  source =
    {
      x86_64-linux = {
        target = "x86_64-unknown-linux-musl";
        hash = "sha256-ECzq8XPvd2vsszIiFun2tcrvmXxADF0V8RLOTeQKH1o=";
      };
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-Kaf63q+wYvPllUsauMaeFNyiT14GHNjTseobqzhaN1Q=";
      };
    }.${platform} or (throw "Unsupported FFF MCP platform: ${platform}");
in
stdenvNoCC.mkDerivation {
  pname = "fff-mcp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dmtrKovalenko/fff.nvim/releases/download/v${version}/fff-mcp-${source.target}";
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
