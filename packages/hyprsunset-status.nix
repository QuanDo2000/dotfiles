{ stdenv, rustc }:
stdenv.mkDerivation {
  pname = "hyprsunset-status";
  version = "0.1.0";
  src = ../rust/hyprsunset-status/main.rs;
  dontUnpack = true;
  nativeBuildInputs = [ rustc ];
  buildPhase = ''
    runHook preBuild
    rustc --edition=2024 -C opt-level=2 -o hyprsunset-status "$src"
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 hyprsunset-status "$out/bin/hyprsunset-status"
    runHook postInstall
  '';
}
