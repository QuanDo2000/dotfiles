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

  npmDepsHash = "sha256-AdZ2ggkZd+6ol5cKYxedpe712q5G9yg+nye+LuNRgRU=";
  npmFlags = [ "--omit=dev" "--ignore-scripts" "--legacy-peer-deps" ];
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp package.json package-lock.json "$out/"
    cp -R node_modules "$out/"
    ln -s ../node_modules/.bin/qmd "$out/bin/qmd"
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
    "$out/bin/qmd" --version | grep -q '^qmd '
  '';

  meta = {
    description = "Integrity-locked Pi extension dependency closure";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
