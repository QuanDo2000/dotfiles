{ buildNpmPackage, lib, nodejs }:

let
  pins = builtins.fromJSON (builtins.readFile ./pi-extensions-release.json);
  source = ../config/shared/ai/pi/extensions;
  lockHash = builtins.hashFile "sha256" (source + "/package-lock.json");
in
assert lockHash == pins.releaseId;
assert nodejs.version == pins.node.version;
buildNpmPackage {
  pname = "pi-extensions";
  version = builtins.substring 0 12 pins.releaseId;
  src = source;

  npmDepsHash = "sha256-LEse9bv9n2A0B1lDtFOGHizcrldrWfJ1uGdy9DhvtEc=";
  npmFlags = [ "--omit=dev" "--ignore-scripts" "--legacy-peer-deps" ];
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp package.json package-lock.json "$out/"
    cp -R node_modules "$out/"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs ];
  installCheckPhase = ''
    node - <<'NODE'
const root = process.env.out;
const expected = require(`''${root}/package.json`).dependencies;
for (const [name, version] of Object.entries(expected)) {
  const actual = require(`''${root}/node_modules/''${name}/package.json`).version;
  if (actual !== version) throw new Error(`''${name}: expected ''${version}, got ''${actual}`);
}
NODE
  '';

  meta = {
    description = "Integrity-locked Pi extension dependency closure";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
