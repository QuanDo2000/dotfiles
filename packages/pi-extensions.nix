{ buildNpmPackage, fetchurl, lib, nodejs, stdenv }:

let
  pins = builtins.fromJSON (builtins.readFile ./pi-extensions-release.json);
  source = ../config/shared/ai/pi/extensions;
  lockHash = builtins.hashFile "sha256" (source + "/package-lock.json");
  asset = pins.betterSqlite3.assets.${stdenv.hostPlatform.system}
    or (throw "Unsupported Pi extension platform: ${stdenv.hostPlatform.system}");
  betterSqlite3 = fetchurl {
    url = "https://github.com/WiseLibs/better-sqlite3/releases/download/v${pins.betterSqlite3.version}/${asset.file}";
    inherit (asset) hash;
  };
in
assert lockHash == pins.releaseId;
assert nodejs.version == pins.node.version;
buildNpmPackage {
  pname = "pi-extensions";
  version = builtins.substring 0 12 pins.releaseId;
  src = source;

  npmDepsHash = "sha256-3BNQln9VaFHLW0YFRILBq2AoeYv4A/XtWTUv36EVqP4=";
  npmFlags = [ "--omit=dev" "--ignore-scripts" "--legacy-peer-deps" ];
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp package.json package-lock.json "$out/"
    cp -R node_modules "$out/"
    tar -xzf ${betterSqlite3} -C "$out/node_modules/better-sqlite3"
    test -f "$out/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
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
