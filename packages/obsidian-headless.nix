{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.14";

  src = fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha256-73UpjtOjVtyypN6Yxu/hCyrGSwBVYAcRi2rHBTXnMVY=";
  };

  npmDepsHash = "sha256-Pcy6hxgc9MyTe/a7bE4pMtXjG9hx4HNwZgbfIzTtVRQ=";

  dontNpmBuild = true;

  postPatch = ''
    cp ${./obsidian-headless-package-lock.json} package-lock.json
  '';

  meta = {
    description = "Headless client for Obsidian services";
    homepage = "https://github.com/obsidianmd/obsidian-headless";
    license = lib.licenses.unfree;
    mainProgram = "ob";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
