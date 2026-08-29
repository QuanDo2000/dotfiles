{ lib, buildNpmPackage, fetchurl, jq, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.84.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-W852bRnDzroY8/uq2RxEnJ+dc5gfnjQA7O+TIAbwaWg=";
  };

  npmDepsHash = "sha256-qehCRHtAPu1TS6zDPA5UgJ1ScUuRX3CmZhRoIQd3HM0=";
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
