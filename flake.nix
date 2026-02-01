{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    services-flake.url = "github:juspay/services-flake";
    process-compose.url = "github:Platonic-Systems/process-compose-flake";
    agenix-shell.url = "github:aciceri/agenix-shell";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      imports = [
        #inputs.agenix-shell.flakeModules.default
        inputs.git-hooks.flakeModule
        inputs.process-compose.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      # agenix-shell.secrets = {
      #   ghToken.file = ./ghToken.age;
      # };

      perSystem =
        {
          config,
          lib,
          pkgs,
          system,
          ...
        }:
        {
          #NOTE: Any changes to pre-commit must be reviewed by eveeifyeve.
          #NOTE: Commit hook checker.
          pre-commit.settings.hooks = {
            treefmt.enable = true;
            deadnix.enable = true;
            flake-checker.enable = true;

            commitizen.enable = true;
            check-merge-conflicts.enable = true;
            no-commit-to-branch.enable = true;

            clippy.enable = true;
            clippy.settings.denyWarnings = true;
          };

          #NOTE: Any changes to treefmt must be reviewed by eveeifyeve.
          #NOTE: Formatter.
          treefmt = {
            projectRootFile = ".git/config";
            flakeCheck = true;
            programs = {
              statix.enable = true;
              nixfmt.enable = true;
              rustfmt.enable = true;
              yamlfmt.enable = true;
              yamllint.enable = true;
              taplo.enable = true;
              keep-sorted.enable = true;
            };
          };

          process-compose.start = {
            imports = [
              inputs.services-flake.processComposeModules.default
            ];

            services.redis.rd = {
              enable = true;
            };

            services.postgres.pg = {
              enable = true;
              initialDatabases = [
                {
                  name = "postgres";
                  schemas = [ ];
                }
              ];
            };

            services.pgadmin.pgad = {
              enable = true;
              initialEmail = "dev@digitalbrewstudios.com";
              initialPassword = "developer";
            };

          };

          devShells.default =
            pkgs.mkShell.override
              {
                stdenv =
                  if pkgs.stdenv.hostPlatform.isElf then
                    pkgs.stdenvAdapters.useWildLinker pkgs.stdenv
                  else
                    pkgs.stdenv;
              }
              {
                inputsFrom = [ config.process-compose.start.services.outputs.devShell ];

                nativeBuildInputs = with pkgs; [
                  config.packages.start
                  rustc
                  cargo
                  bacon
                  cargo-nextest
                  sea-orm-cli
                ];

                buildInputs = with pkgs; [
                  #(lib.optionals pkgs.stdenv.isDarwin pkgs.apple-sdk_15)
                  rust-analyzer
                  config.formatter
                  clippy
                ];

                shellHook = ''
                  ${config.pre-commit.shellHook}
                '';

                RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

                DATABASE_URL = config.process-compose.start.services.postgres.pg.connectionURI {
                  dbName = "postgres";
                };
                CACHE_DATABASE_URL =
                  with config.process-compose.start.services.redis.rd;
                  "redis://${bind}:${toString port}";
              };
        };

    };
}
