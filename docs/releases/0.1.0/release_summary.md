# Release Summary: Keystone v0.1.0

**Release Date**: 2025-11-08 (retroactive tag, cut 2026-03-03)
**Release Channel**: alpha
**Tag**: v0.1.0

## Actions Taken

- [x] CHANGELOG.md created with Keep a Changelog format ([`4864d34`](https://github.com/ncrmro/keystone/commit/4864d34))
- [x] Git tag `v0.1.0` created (annotated) at commit `59ffa5f`
- [ ] Release branch — skipped (alpha release, not needed)
- [x] Tag pushed to origin
- [x] CHANGELOG commit pushed to origin
- [ ] GitHub release — `gh` not authenticated in sandbox. Create manually with command below.

### Manual GitHub Release

Run this from an authenticated environment:

```bash
gh release create v0.1.0 \
  --repo ncrmro/keystone \
  --title "Keystone v0.1.0 — First Working Desktop" \
  --notes-file releases/0.1.0/release_notes.md \
  --prerelease
```

## Release Links

- **Tag**: https://github.com/ncrmro/keystone/tree/v0.1.0
- **Changelog Diff**: https://github.com/ncrmro/keystone/compare/06fbb40...v0.1.0
- **GitHub Release**: Pending manual creation (see above)

## CI/CD Automation Recommendations

### Recommended GitHub Actions Workflows

#### Release Workflow (tag-triggered)

Trigger on `v*` tag push. Should:

1. Run `nix flake check` (already in `test.yml`, extend to tag events)
2. Build ISO: `nix build .#iso`
3. Create GitHub Release with release notes from `releases/[version]/release_notes.md`
4. Attach ISO artifact to the release
5. Optionally push to Cachix for binary cache availability

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v31
        with:
          nix_path: nixpkgs=channel:nixos-unstable
      - name: Check flake
        run: nix flake check
      - name: Build ISO
        run: nix build .#iso
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: result/iso/*.iso
          prerelease: ${{ contains(github.ref, 'alpha') || contains(github.ref, 'beta') || contains(github.ref, 'rc') }}
          generate_release_notes: true
```

#### Changelog Validation (PR check)

Add a PR check that ensures CHANGELOG.md is updated for feature and fix PRs:

```yaml
# Add to .github/workflows/test.yml
changelog-check:
  if: startsWith(github.head_ref, 'feat/') || startsWith(github.head_ref, 'fix/')
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Check CHANGELOG updated
      run: |
        if ! git diff origin/main...HEAD --name-only | grep -q CHANGELOG.md; then
          echo "::error::CHANGELOG.md not updated. Please add an entry for your changes."
          exit 1
        fi
```

#### Version Bump Automation

Consider `release-please` for automated release management:

- Reads conventional commits (`feat()`, `fix()`, etc.) landing on main
- Automatically creates a "release PR" that bumps version and updates CHANGELOG.md
- Merging the release PR triggers the tag-based release workflow above
- Particularly valuable since Keystone already uses conventional commits

### Implementation Priority

1. **Tag-triggered release workflow** — biggest time savings, creates consistent releases with ISO artifacts
2. **Changelog validation PR check** — prevents changelog debt, easy to add to existing `test.yml`
3. **Release-please automation** — full hands-off release cycle once the first two are in place

## Notes

- This is Keystone's first formal release. All prior development was on main with no version tags.
- The tag points to commit `59ffa5f` from 2025-11-08, marking the "first working desktop" milestone.
- The CHANGELOG.md commit is on HEAD (2026-03-03), after the tagged commit. This is normal for retroactive releases.
- The `releases/0.1.0/` directory in the repo contains all planning artifacts (audit, scope, announcement, notes) for reference.
- `gh` authentication was not available in the sandbox environment. The GitHub release needs to be created manually.
- The `latest-iso` tag still exists from before this release process — consider removing it once release automation is in place.
