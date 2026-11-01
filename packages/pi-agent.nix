{ lib, buildNpmPackage, fetchurl, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "1.4.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-0VXBbvb6AJYPv1iykRU26AsF8zcA4LFPvQiWft4MdCg=";
  };

  npmDepsHash = "sha256-FzYzTlweKWBU+04Idpkzk6n/K++wHEIJfTJluTdfVbg=";
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
