{ lib, buildNpmPackage, fetchurl, jq, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.84.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-0H3EF/eKFNrDdqh4tlVrUZYfEY95dx7jdTM9xRNWvHU=";
  };

  npmDepsHash = "sha256-QPAnjOkuJsiAh5imcGHJYurcNzJ5kM1z0jZFYiqQsoo=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  nativeBuildInputs = [ makeWrapper python3 ];

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
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
