{
  description = "zap dev shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # required for latest zig
    zig.url = "github:mitchellh/zig-overlay";

    # required for latest neovi    # Used for shell.nix
    flake-compat = {
      url = github:edolstra/flake-compat;
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
      })
    ];
    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system; };
      in rec {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            zigpkgs."0.11.0"
            curl
            # hexedit
            bvi
          ];

          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
          '';
        };

        # shell that provides zig 0.11.0 via overlay 
        # use it for just building locally, via zig build
        devShells.build = pkgs.mkShell {
          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
            zigpkgs."0.11.0"
            curl
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
          '';
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;

        defaultPackage = packages.binaryformdata-linux;

        # build the app with nix for LINUX (linux musl) 
        # -- change zig build below for mac for now
        # nix build .#binaryformdata-linux
        packages.binaryformdata-linux = pkgs.stdenvNoCC.mkDerivation {
          name = "binaryformdata";
          version = "master";
          src = ./.;
          buildInputs = [ pkgs.zigpkgs."0.11.0" ];
          dontConfigure = true;
          dontInstall = true;


          postPatch = ''
            mkdir -p .cache
            ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
          '';

          buildPhase = ''
            mkdir -p $out
            mkdir -p .cache/{p,z,tmp}
            zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
            cp -pr data $out/bin/

            # apparently not neccesary to link the path later in the docker image
            # mkdir -p tmp
            '';
        };



        # the following produces the exact same image size
        # note: the following only works if you build on linux I guess
        # 
        # Usage:
        #    nix build .#docker
        #    docker load < result
        #    docker run -p5000:5000 binaryformdata:lastest
        packages.docker = pkgs.dockerTools.buildImage { # helper to build Docker image
          name = "binaryformdata";                         # give docker image a name
          tag = "latest";                               # provide a tag
          created = "now";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ packages.binaryformdata-linux.out ];  # .out seems to not make a difference
            pathsToLink = [ "/bin" "/tmp"];
          };

          # facil.io needs a /tmp
          # update: pathsToLink /tmp above seems to do the trick

          config = {

            Cmd = [ "/bin/binaryformdata" ];
            WorkingDir = "/bin";

            ExposedPorts = {
              "5000/tcp" = {};
            };

          };
        };

      }
    );
  
}
