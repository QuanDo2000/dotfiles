{ lib, buildNpmPackage, fetchurl, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "1.5.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-aRveGGJztFfZ0cQdD9R7V4U7XoXe0a3Rofa3jmbCYfQ=";
  };

  npmDepsHash = "sha256-p47HeCWOJrhtR6bDMFG7q4XrVcHSr59NtDBve5vlwaE=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  nativeBuildInputs = [ makeWrapper python3 ];

  postPatch = ''
    ${lib.getExe nodejs} -e 'const fs = require("node:fs"); const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8")); delete packageJson.devDependencies; fs.writeFileSync("package.json", JSON.stringify(packageJson));'
    cp ${./pi-agent-npm-shrinkwrap.json} npm-shrinkwrap.json
  '';

  preInstall = ''
    python3 ${../scripts/patch_pi_compaction.py} dist/core/agent-session.js dist/bundle
  '';

  postFixup = ''
    wrapProgram $out/bin/pi --prefix PATH : "${lib.makeBinPath [ nodejs ]}"
  '';

  meta = {
    description = "Minimal terminal coding harness";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
