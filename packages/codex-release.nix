{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:

let
  version = "0.147.0";
  linuxHash = "sha256-vXWNU9VuQdxl4EX0WJ33mgOO0ZegEa3LUqJY5q1kz9o=";
  darwinHash = "sha256-uFGUP//EiqfFwTC2o0vgmWSDPSeFVG7altdJQnxuJPI=";
  platform = stdenvNoCC.hostPlatform.system;
  source =
    {
      x86_64-linux = {
        url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
        hash = linuxHash;
      };
      aarch64-darwin = {
        url = "https://github.com/openai/codex/releases/download/rust-v${version}/openai_codex_cli_bin-${version}-py3-none-macosx_11_0_arm64.whl";
        hash = darwinHash;
      };
    }.${platform} or (throw "Unsupported Codex platform: ${platform}");
in
stdenvNoCC.mkDerivation ({
  pname = "codex";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R ${
      if stdenvNoCC.hostPlatform.isDarwin then
        "codex_cli_bin/bin codex_cli_bin/codex-path codex_cli_bin/codex-resources codex_cli_bin/codex-package.json"
      else
        "bin codex-path codex-resources codex-package.json"
    } "$out/"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenAI Codex command-line interface";
    license = licenses.asl20;
    homepage = "https://github.com/openai/codex";
    mainProgram = "codex";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
} // lib.optionalAttrs stdenvNoCC.hostPlatform.isDarwin {
  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip "$src"
    runHook postUnpack
  '';
})
