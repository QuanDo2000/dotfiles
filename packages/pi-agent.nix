{ lib, buildNpmPackage, fetchurl, jq, makeWrapper, nodejs }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.83.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-cJf+Szh2Ldp+x4AB57kEMMhJ+69xcyW/6BCXROMiVeY=";
  };

  npmDepsHash = "sha256-G8+n5dBfPI/nDn3j975yaLZaC6u13IEyzMcnkp2xKmQ=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./pi-agent-npm-shrinkwrap.json} npm-shrinkwrap.json
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
