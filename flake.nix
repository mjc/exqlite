{
  description = "Development environment for exqlite (Elixir SQLite3 NIF)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        lib = pkgs.lib;
        erlang = pkgs.beam.interpreters.erlang_28;
        beamPackages = pkgs.beam.packagesWith erlang;
        elixir = beamPackages.elixir_1_19;
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs =
            [
              erlang
              elixir
              beamPackages.hex
              beamPackages.rebar
              beamPackages.rebar3
              pkgs.zig
              pkgs.git
              pkgs.gh
              pkgs.sqlite
            ]
            ++ lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools
            ++ lib.optionals pkgs.stdenv.isDarwin [pkgs.apple-sdk];

          shellHook = ''
            export ERL_AFLAGS="-kernel shell_history enabled"
            export ERTS_INCLUDE_DIR="$(erl -noshell -eval \
              'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]).' \
              -s init stop)"
          '';
        };

        devShells.system-sqlite = pkgs.mkShell {
          nativeBuildInputs =
            [
              erlang
              elixir
              beamPackages.hex
              beamPackages.rebar
              beamPackages.rebar3
              pkgs.zig
              pkgs.sqlite
              pkgs.git
            ]
            ++ lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools
            ++ lib.optionals pkgs.stdenv.isDarwin [pkgs.apple-sdk];

          shellHook = ''
            export ERL_AFLAGS="-kernel shell_history enabled"
            export EXQLITE_USE_SYSTEM=1
            export ERTS_INCLUDE_DIR="$(erl -noshell -eval \
              'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]).' \
              -s init stop)"
          '';
        };
      }
    );
}
