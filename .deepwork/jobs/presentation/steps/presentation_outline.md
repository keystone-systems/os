# Create Presentation Outline

## Objective

Build a complete slide-by-slide outline that weaves together the key messages,
narrative arc, speaker notes, and media placements into a coherent plan before
any Slidev code is written.

## Task

Read `presentation_requirements.md` and `presentation_media_manifest.md`, then compose the
outline. Assign each media asset to the slide where it has the most impact.
Insert TODO placeholders for any unfilled media slots.

### Process

1. **Design the narrative arc**:
   - **Opening** (1–2 slides): Hook, agenda, why this matters to the audience
   - **Body** (bulk): One section per key message, each with supporting evidence
   - **Closing** (1–2 slides): Summary, call-to-action, Q&A prompt

2. **Assign media** — for each asset in `presentation_media_manifest.md`, place it on the
   slide matching the `Suggested slide` column. If no slide matches, create one or
   adjust the placement. Unresolved slots get `<!-- TODO: add image of <X> -->`.

3. **Write one section per slide** — see Output Format below.

4. **Validate slide count** — ensure total slides are within ±2 of the target from
   `presentation_requirements.md`. If outside that range, add or remove slides and note
   the adjustment.

## Output Format

### presentation_outline.md

```markdown
# Presentation outline: Keystone infrastructure overview

**Total slides**: 13  **Target**: 13  **Duration**: 20 min

---

## Slide 1 — Keystone: your infrastructure, fully declared
**Layout**: cover
**Key points**:
- (subtitle) One diff to rule them all
**Speaker notes**: Open with the diff demo — show a single line of Nix that adds
  a full service. Let the audience absorb the implications before saying anything.
**Media**: none

---

## Slide 2 — What Keystone manages
**Layout**: two-cols
**Key points**:
- Left: OS, secrets, users, services
- Right: dev tooling, agents, monitoring
**Speaker notes**: Keep this overview fast — 60 seconds. The goal is to set scope,
  not explain every module.
**Media**: none

---

## Slide 3 — The server rack
**Layout**: image-right
**Key points**:
- Hardware is commodity; config is code
**Speaker notes**: Point out that none of these machines have been SSHed into
  manually since Keystone was adopted.
**Media**: ![Server rack](presentations/keystone-overview/_dataroom/media/a1b2c3_rack.jpg)

---

## Slide 5 — Hardware key unlock
**Layout**: default
**Key points**:
- Secrets are released by TPM + YubiKey at boot
**Speaker notes**: Emphasize: even with physical access to the disk, an attacker
  cannot read the secrets without the key.
**Media**: <!-- TODO: add photo of YubiKey — not found in Immich search -->
```

## Quality Criteria

- The outline follows a coherent narrative arc: opening hook → body sections →
  closing call-to-action
- Every slide has speaker notes explaining what to say (not just what's on the slide)
- Every media asset from the manifest appears on at least one slide
- Unresolved media slots are marked with a TODO comment containing a concrete
  description of what is needed
- Total slide count is within ±2 of the target in presentation_requirements.md

## Context

This step is the planning gate before `presentation_build_deck`. A solid outline prevents
the deck-building step from having to make structural decisions. Reviewers will check
that the narrative arc is clear, so invest time here rather than in the Slidev syntax.
