{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.12";

  src = fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha256-bSZ/1XdTEgAH4atw/NPx0OsP2ul78T1ea4xpu+7w/n0=";
  };

  npmDepsHash = "sha256-uXNgBQ02JeG741W4F5I7TXwsd6MBPFa6w6BFO1fmM+4=";

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
