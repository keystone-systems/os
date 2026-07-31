# Agenix recipients file.
#
# This file tells `agenix -e <file>.age` which public keys an encrypted secret
# should be readable by. agenix does NOT read this file at OS-build time —
# it's a tool-side manifest for re-encryption. The actual `age.secrets.*`
# declaration on each host (in flake.nix or hosts/<host>/configuration.nix)
# is what wires the runtime decryption.
#
# Uncomment the entries you need when you reach Step 8 of
# docs/keystone/onboarding.md. See docs/keystone/github-token.md for how the
# pubkeys are derived (ssh-to-age on the user's id_ed25519.pub and the host's
# /etc/ssh/ssh_host_ed25519_key.pub).

# let
#   # Driver/user keys — anyone who can edit secrets in this repo.
#   users = {
#     # Run `ssh-to-age -i ~/.ssh/id_ed25519.pub` to derive this from your
#     # existing SSH pubkey, or use a dedicated age key from `age-keygen`.
#     # <username> = "age1...";
#   };
#
#   # Host keys — machines that decrypt secrets at runtime.
#   # Derive each via:
#   #   ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
#   # on the target host (after first boot — fresh installs generate the
#   # host keys at first boot via sshd-keygen.target, before sshd starts).
#   systems = {
#     # laptop = "age1...";
#     # server = "age1...";
#   };
#
#   adminKeys = builtins.attrValues users;
# in
# {
#   # Example: one secret readable by all users + the laptop host at runtime.
#   # Rename <username> to match the value in flake.nix `admin.username`.
#   #
#   # "secrets/<username>-github-token.age".publicKeys =
#   #   adminKeys ++ [ systems.laptop ];
# }

# Stub: agenix reads this file to find an attrset. Returning an empty set
# keeps `agenix` happy until you uncomment real entries above.
{
}
