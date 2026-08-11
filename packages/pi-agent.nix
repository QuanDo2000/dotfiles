{ lib, buildNpmPackage, fetchurl, jq, makeWrapper, nodejs, python3 }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.84.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-ppoYWWAX6RlV/Q/Wd75p+rW26gHVsGIHvO407hUivCA=";
  };

  npmDepsHash = "sha256-FfwODI+m5Jts0PrjA9mFa+Mp9QT17/ejixg84RGXGe4=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  nativeBuildInputs = [ makeWrapper python3 ];

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./pi-agent-npm-shrinkwrap.json} npm-shrinkwrap.json
    python3 ${../scripts/patch_pi_compaction.py} dist/core/agent-session.js
    substituteInPlace dist/core/slash-commands.js \
      --replace-fail '{ name: "quit", description:' '{ name: "exit", description:'
    substituteInPlace dist/modes/interactive/interactive-mode.js \
      --replace-fail 'text === "/quit"' 'text === "/exit"'
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
