{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  zlib,
}:

let
  pins = builtins.fromJSON (builtins.readFile ./codebase-memory-mcp-release.json);
  inherit (pins) version;
  platform = stdenv.hostPlatform.system;
  source =
    {
      x86_64-linux = pins.linux.amd64;
      aarch64-darwin = pins.darwin.arm64;
    }.${platform} or (throw "Unsupported codebase-memory-mcp platform: ${platform}");
in
stdenv.mkDerivation {
  pname = "codebase-memory-mcp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/DeusData/codebase-memory-mcp/releases/download/v${version}/${source.file}";
    hash = source.nixHash;
  };

  sourceRoot = ".";
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib zlib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 codebase-memory-mcp "$out/bin/codebase-memory-mcp"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Local codebase knowledge-graph MCP server with graph UI";
    homepage = "https://github.com/DeusData/codebase-memory-mcp";
    license = licenses.mit;
    mainProgram = "codebase-memory-mcp";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
