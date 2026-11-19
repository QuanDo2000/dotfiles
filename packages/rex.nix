{ lib, stdenvNoCC, fetchurl, _7zz, makeBinaryWrapper }:

let
  release = builtins.fromJSON (builtins.readFile ./rex-release.json);
in
stdenvNoCC.mkDerivation {
  pname = "rex";
  version = "${release.version}-${release.build}";
  src = fetchurl { inherit (release) url hash; };
  nativeBuildInputs = [ _7zz makeBinaryWrapper ];
  sourceRoot = ".";
  postUnpack = ''
    # The upstream DMG changed both its volume and app names in build 2061.
    apps=()
    for candidate in "Rex/Rex.app" "Rex Beta/Rex Beta.app"; do
      if [[ -d "$candidate" ]]; then
        apps+=("$candidate")
      fi
    done
    if [[ "''${#apps[@]}" != 1 ]]; then
      echo "Expected exactly one Rex app bundle in the DMG; found ''${#apps[@]}" >&2
      exit 1
    fi
    app="$PWD/''${apps[0]}"
    helper="Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R "$app" "$out/Applications/"
    makeBinaryWrapper "$out/Applications/''${app##*/}/$helper" "$out/bin/rex"
    runHook postInstall
  '';

  # Preserve upstream's notarized bundle; changing Mach-O files invalidates it.
  dontFixup = true;
  doInstallCheck = true;
  installCheckPhase = ''
    # Inspect the identical unpacked bundle, not the output: macOS registers
    # inspected .apps with TCC and can prevent Nix finalizing their ownership.
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = '${release.version}'
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = '${release.build}'
    /usr/bin/codesign --verify --deep --strict \
      --test-requirement='=anchor apple generic and certificate leaf[subject.OU] = "AG92C3PT77"' "$app"
    "$app/$helper" version
    "$app/$helper" config check ${../config/rex/init.lua}
  '';

  meta = {
    description = "Rex terminal and persistent session multiplexer (preview)";
    homepage = "https://www.superlogical.com/rex";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.darwin;
    mainProgram = "rex";
  };
}
