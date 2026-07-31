#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nodejs cacert curl jq
# shellcheck shell=bash

set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-2.0.53}"

echo "Fetching claude-code version $VERSION from npm..."

# Download the package tarball
TARBALL_URL="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${VERSION}.tgz"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

curl -sL "$TARBALL_URL" | tar -xz -C "$TMP_DIR"

# Copy package-lock.json if it exists, otherwise generate it
if [ -f "$TMP_DIR/package/package-lock.json" ]; then
    echo "Copying package-lock.json from package..."
    cp "$TMP_DIR/package/package-lock.json" ./package-lock.json
else
    echo "Generating package-lock.json..."
    cd "$TMP_DIR/package"
    npm install --package-lock-only --ignore-scripts
    cd -
    cp "$TMP_DIR/package/package-lock.json" ./package-lock.json
fi

echo "package-lock.json created successfully!"
echo "Now run: nix build .#claude-code --impure"
echo "Then update the hashes in default.nix based on the error messages."
