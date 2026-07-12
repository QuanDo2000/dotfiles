{ lib, buildNpmPackage, fetchurl, jq }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.80.6";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha512-vcfD6tOk402isLl3Cm/qbn2O10TvgroMp1+/fEGM24ZdvETFCdOYv5VZ7m59EI5fPsjfSJh+CpQ5bhBrhfOg7g==";
  };

  npmDepsHash = "sha256-xwn6zBV6QmLPaf9Ht2y1smJSUTMw1DYmPFBvPGVgvCc=";
  dontNpmBuild = true;
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    substituteInPlace dist/core/slash-commands.js \
      --replace-fail '{ name: "quit", description:' '{ name: "exit", description:'
    substituteInPlace dist/modes/interactive/interactive-mode.js \
      --replace-fail 'text === "/quit"' 'text === "/exit"'
    substituteInPlace npm-shrinkwrap.json \
      --replace-fail '"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.80.6.tgz",' '"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.80.6.tgz", "integrity": "sha512-Lvn89ko42h5ETUb6Z0Ku6ldskEqXaTdQBYvSa0+7bdG9V6rUEpXptv5e0OVZ1HDcvi8s6/2lGCQWsxKX+DFHNw==",' \
      --replace-fail '"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.80.6.tgz",' '"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.80.6.tgz", "integrity": "sha512-7xfLk8sANBp+bpPEbjoOZTbPxsa+++b1JXAoSJsNa3vbs9AHHEclmvg54XLQcxH+fuwaeti/g2jeIfJ+mVYLpA==",' \
      --replace-fail '"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.80.6.tgz",' '"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.80.6.tgz", "integrity": "sha512-bSuzS4EVSqEPj/Qr/p9eqCESfKsGuDNbl77EGci8Iaqqt/C/XCBZL1MjXaxSWW1NsT5afjp/Cb0NTPzOLv/aPA==",'
  '';

  meta = {
    description = "Minimal terminal coding harness";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
