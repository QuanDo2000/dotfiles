{ buildNpmPackage, lib, nodejs, pi-agent }:

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

  npmDepsHash = "sha256-84ZI51Hb9ikPBSnaQ6iHMJ62gKtgy3N502jk27wl7EY=";
  npmFlags = [ "--omit=dev" "--ignore-scripts" "--legacy-peer-deps" ];
  dontNpmBuild = true;
  preInstall = ''
    node ${../scripts/patch_pi_web_activation.cjs} node_modules/pi-web-access/dist/index.js
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp package.json package-lock.json "$out/"
    cp -R node_modules "$out/"
    ln -s ../node_modules/.bin/qmd "$out/bin/qmd"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs pi-agent ];
  installCheckPhase = ''
    node ${../scripts/patch_pi_web_activation.cjs} "$out/node_modules/pi-web-access/dist/index.js" --check
    node - <<'NODE'
const root = process.env.out;
const expected = require(`''${root}/package.json`).dependencies;
for (const [name, version] of Object.entries(expected)) {
  const actual = require(`''${root}/node_modules/''${name}/package.json`).version;
  if (actual !== version) throw new Error(`''${name}: expected ''${version}, got ''${actual}`);
}
NODE
    "$out/bin/qmd" --version | grep -q '^qmd '
    node ${../tests/ai/pi-web-activation-smoke.mjs} ${lib.getExe pi-agent} "$out/node_modules/pi-web-access/dist/index.js"
  '';

  meta = {
    description = "Integrity-locked Pi extension dependency closure";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
