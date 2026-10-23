# Targeted security updates until the nixpkgs pin includes eMudhra distrust.
# https://nodejs.org/en/blog/release/v26.12.1
# https://nodejs.org/en/blog/release/v24.22.1
final: prev:
let
  updateNode =
    package: version: sha256:
    if final.lib.versionAtLeast package.version version then
      package
    else
      package.overrideAttrs (old: {
        inherit version;
        # Security releases need the bundled Brotli fix/new error constant;
        # the pinned shared Brotli 1.2.0 cannot build or supply that fix.
        configureFlags = builtins.filter (
          flag: !(final.lib.hasPrefix "--shared-brotli" flag)
        ) old.configureFlags;
        src = final.fetchurl {
          url = "https://nodejs.org/dist/v${version}/node-v${version}.tar.xz";
          inherit sha256;
        };
        passthru = old.passthru // {
          tests = old.passthru.tests // {
            version = final.testers.testVersion {
              package = final."nodejs-slim_${final.lib.versions.major version}";
              version = "v${version}";
            };
          };
        };
      });
in
{
  nodejs-slim_26 =
    updateNode prev.nodejs-slim_26 "26.12.1"
      "053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c";
  nodejs-slim_24 =
    updateNode prev.nodejs-slim_24 "24.22.1"
      "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";

  # Keep the build-time dependency graph unchanged; select this for user TLS.
  emudhra-cacert = prev.cacert.override {
    blacklist = [
      "emSign Root CA - C1"
      "emSign ECC Root CA - C3"
      "emSign ECC Root CA - G3"
    ];
  };

  # 1.4.2 accepts the compromised-chain probe; 1.4.4 rejects it (CERT_REVOKED).
  bun =
    if final.lib.versionAtLeast prev.bun.version "1.4.4" then
      prev.bun
    else
      prev.bun.overrideAttrs (
        attrs: old: {
          version = "1.4.4";
          src = attrs.passthru.sources.${final.stdenv.hostPlatform.system};
          passthru = old.passthru // {
            sources =
              final.lib.mapAttrs
                (
                  system: hash:
                  final.fetchurl {
                    url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/${
                      {
                        x86_64-linux = "bun-linux-x64-baseline";
                        aarch64-linux = "bun-linux-aarch64";
                        aarch64-darwin = "bun-darwin-aarch64";
                      }
                      .${system}
                    }.zip";
                    inherit hash;
                  }
                )
                {
                  x86_64-linux = "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
                  aarch64-linux = "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
                  aarch64-darwin = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
                };
          };
        }
      );
}
