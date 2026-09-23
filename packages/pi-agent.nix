{ lib, buildNpmPackage, fetchurl, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.87.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-FCPuPGHnyWRk4cvzyNwk0wVss0EJlcNnGpjD7MUnVA8=";
  };

  npmDepsHash = "sha256-g7xLIxQbKLO/l09bQKE+knAF5+tgO3hzn3UXgFIJZrg=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  nativeBuildInputs = [ makeWrapper python3 ];

  postPatch = ''
    ${lib.getExe nodejs} -e 'const fs = require("node:fs"); const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8")); delete packageJson.devDependencies; fs.writeFileSync("package.json", JSON.stringify(packageJson));'
    cp ${./pi-agent-npm-shrinkwrap.json} npm-shrinkwrap.json
  '';

  preInstall = ''
    python3 ${../scripts/patch_pi_compaction.py} dist/core/agent-session.js
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
