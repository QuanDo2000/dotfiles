{ lib, appimageTools, fetchurl }:

let
  pname = "webcord";
  version = "4.14.0";
  src = fetchurl {
    url = "https://github.com/SpacingBat3/WebCord/releases/download/v${version}/WebCord-${version}-x64.AppImage";
    hash = "sha256-ZtwpF09giiFrBKA17QNtnsJNBr3UcuylxarOdHt3MRw=";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 ${contents}/WebCord.desktop $out/share/applications/webcord.desktop
    install -Dm644 ${contents}/webcord.png $out/share/icons/hicolor/256x256/apps/webcord.png
  '';

  meta = {
    description = "Discord and SpaceBar client implemented without Discord API";
    homepage = "https://github.com/SpacingBat3/WebCord";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "webcord";
  };
}
