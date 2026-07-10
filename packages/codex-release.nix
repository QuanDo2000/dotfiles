{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  pname = "codex";
  version = "0.144.1";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-P9UM+WgJse6ilLv7oKXDpXaHG0h2ofDpEiblIMGSO+E=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R bin codex-path codex-resources codex-package.json "$out/"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenAI Codex command-line interface";
    license = licenses.asl20;
    homepage = "https://github.com/openai/codex";
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
  };
}
