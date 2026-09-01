{ buildNpmPackage, lib, nodejs, python3 }:

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

  npmDepsHash = "sha256-DViDeJOIkS3T2n+Cc1/4htWGpbBQWaqWo9YW9i2nW5A=";
  npmFlags = [ "--omit=dev" "--ignore-scripts" "--legacy-peer-deps" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ python3 ];

  preInstall = ''
    python3 ${../scripts/patch_pi_hermes_background_flush.py} node_modules/pi-hermes-memory
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp package.json package-lock.json "$out/"
    cp -R node_modules "$out/"
    platform="$(node -p 'process.platform + "-" + process.arch')"
    test -f "$out/node_modules/better-sqlite3/prebuilds/$platform.node"
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
const Database = require(`''${root}/node_modules/better-sqlite3`);
const db = new Database(':memory:');
db.prepare('select 1').get();
db.close();
NODE
  '';

  meta = {
    description = "Integrity-locked Pi extension dependency closure";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
