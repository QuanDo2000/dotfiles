{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  zlib,
}:

let
  version = "0.9.0";
  platform = stdenv.hostPlatform.system;
  source =
    {
      x86_64-linux = {
        target = "linux-amd64";
        hash = "sha256-wwkBkhugJzjnWdmkY78gWi/jH9j+7UH7hO02TxgBXeo=";
      };
      aarch64-darwin = {
        target = "darwin-arm64";
        hash = "sha256-WS+E5E1ejqua5xNOmbFUDOPCjoS2hCBPjznN5RYg0O4=";
      };
    }.${platform} or (throw "Unsupported codebase-memory-mcp platform: ${platform}");
in
stdenv.mkDerivation {
  pname = "codebase-memory-mcp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/DeusData/codebase-memory-mcp/releases/download/v${version}/codebase-memory-mcp-ui-${source.target}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib zlib ];

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
