{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.10.1";
  platform = stdenvNoCC.hostPlatform.system;
  source =
    {
      x86_64-linux = {
        target = "x86_64-unknown-linux-musl";
        hash = "sha256-wXY3wzOvu73qSwPPPhVzJAxBR64SF1bjY6r6PJ0O+1g=";
      };
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-7/ZmCpxI4+GXLVV8EAPgV+X/mdYDn1+BBnHyEjCT/fw=";
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
