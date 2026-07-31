FROM nixos/nix

# Enable flakes and nix-command
ENV NIX_CONFIG="experimental-features = nix-command flakes"

# Create os-release for devcontainer OS detection
RUN echo 'ID=nixos' > /etc/os-release && \
    echo 'NAME="NixOS"' >> /etc/os-release && \
    echo 'PRETTY_NAME="NixOS (Nix)"' >> /etc/os-release

WORKDIR /workspaces/keystone
