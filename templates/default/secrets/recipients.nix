# Recipients manifest for `ks secrets sync`.
#
# `ks secrets sync` combines this file with the host public keys from the
# flake (converted via ssh-to-age) to generate `.sops.yaml` — the file sops
# actually reads. Never edit `.sops.yaml` by hand; edit this file, run
# `ks secrets sync`, then `ks secrets rekey` to re-encrypt existing files.
#
# Rules:
#   - Every file gets ALL admin recipients.
#   - `secrets/<host>.yaml` automatically gets that host's recipient
#     (host name = filename stem, must exist in the flake host inventory).
#   - `files` adds/overrides host lists for non-per-host files (shared and
#     service scopes). Keys are regexes matched against the file path.
#
# Uncomment and fill in when you reach Step 8 of docs/keystone/onboarding.md.
{
  admins = {
    # Editing keys: either an age/age-plugin-yubikey recipient string or an
    # ssh-ed25519 public key (converted via ssh-to-age at sync time).
    # <username>-laptop = "ssh-ed25519 AAAA...";
    # <username>-yubikey = "age1yubikey1...";
  };
  files = {
    # "secrets/shared\\.yaml".hosts = [ "laptop" "server" ];
    # "secrets/services/k3s\\.yaml".hosts = [ "server" ];
  };
}
