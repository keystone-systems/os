{
  description = "ks development shell and agent container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-agent-sandbox = {
      url = "github:ncrmro/nix-agent-sandbox";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      rust-overlay,
      nix-agent-sandbox,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };
      rust = pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          "rust-src"
          "rust-analyzer"
        ];
      };

      # Unwrapped gemini-cli (no bwrap sandbox)
      gemini-cli = nix-agent-sandbox.packages.${system}.gemini-cli-unwrapped;

      # Common build inputs for Rust development
      rustBuildInputs = with pkgs; [
        openssl
        zlib
      ];

      rustNativeBuildInputs = with pkgs; [
        rust
        clippy
        pkg-config
        cmake
      ];

      # Container image with Gemini + Rust toolchain
      agentImage = pkgs.dockerTools.buildLayeredImage {
        name = "ks-agent";
        tag = "latest";

        contents = with pkgs; [
          # Base system
          bashInteractive
          coreutils
          gnugrep
          gnused
          gawk
          findutils
          procps # pgrep, ps, etc.
          which
          less
          file

          # Git
          git
          openssh

          # Rust toolchain
          rust
          clippy
          pkg-config
          cmake
          gcc

          # Build dependencies
          openssl
          openssl.dev
          zlib
          zlib.dev

          # Gemini CLI
          gemini-cli

          # CA certificates for HTTPS
          cacert
        ];

        config = {
          Env = [
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "PATH=/bin:/usr/bin"
            "HOME=/root"
            "CARGO_HOME=/root/.cargo"
            "RUSTUP_HOME=/root/.rustup"
          ];
          WorkingDir = "/workspace";
          Cmd = [ "/bin/bash" ];
        };
      };

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = rustNativeBuildInputs;
        buildInputs = rustBuildInputs;

        # Let libgit2-sys vendor its own libgit2 to avoid version mismatches
        RUST_SRC_PATH = "${rust}/lib/rustlib/src/rust/library";
      };

      # Container image for agent execution
      packages.${system} = {
        agent-image = agentImage;

        # Script to run gemini in the container
        run-gemini = pkgs.writeShellScriptBin "run-gemini" ''
          set -e

          IMAGE_NAME="ks-agent:latest"
          WORKSPACE="''${1:-$(pwd)}"
          PROMPT="''${2:-}"

          # Load image if not already loaded
          if ! ${pkgs.podman}/bin/podman image exists "$IMAGE_NAME" 2>/dev/null; then
            echo "Loading container image..."
            ${pkgs.podman}/bin/podman load < ${agentImage}
          fi

          # Run gemini in container
          ${pkgs.podman}/bin/podman run --rm -it \
            -v "$WORKSPACE:/workspace:rw" \
            -v "$HOME/.config/gemini:/root/.config/gemini:ro" \
            -v "$HOME/.gitconfig:/root/.gitconfig:ro" \
            -v "$HOME/.ssh:/root/.ssh:ro" \
            -v "$HOME/.cargo/registry:/root/.cargo/registry:rw" \
            -v "$HOME/.cargo/git:/root/.cargo/git:rw" \
            -w /workspace \
            "$IMAGE_NAME" \
            gemini "''${PROMPT:-bash}"
        '';
      };
    };
}
