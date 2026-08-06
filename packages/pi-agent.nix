{ lib, buildNpmPackage, fetchurl, jq, makeWrapper, nodejs }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.84.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-zsqiiNGcOSmH2YxOqoU+u+UgtGUR+k3W2GPOhwTGEpg=";
  };

  npmDepsHash = "sha256-cl6ATh3DmiCXCa3DimNUMg3gbfkkZ9RaSkxtZAWfvwM=";
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
