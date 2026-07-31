# Consumer-flake docs

These files are symlinks to the canonical content under
[`templates/default/docs/keystone/`](../../templates/default/docs/keystone/).
That directory is what `nix flake new -t github:ncrmro/keystone` copies
verbatim into the user's scaffolded repo. Keeping the canonical copy there
means a scaffolded user gets real files (not symlinks) while the keystone
repo's `docs/` view stays in sync without any build step.

Edit the template path — the symlinks here pick up the change automatically.

See [`CONTRIBUTOR.md`](../../CONTRIBUTOR.md) § "Consumer-flake docs sync"
for the full convention, including how to add a new shared doc.
