# Search Media in Immich

## Objective

Query the Immich photo library to find photos, videos, and OCR-indexed screenshots
that are relevant to the presentation. Produce a media manifest so downstream steps
can embed or reference the assets.

## Task

Read `presentation_requirements.md`. If `immich_search` is `no`, write a minimal manifest
and finish. If `yes`, query the Immich API using the search parameters from the
requirements, download the selected assets, and document them in the manifest.

### Process

1. **Check media preference** — read `presentation_requirements.md`. If `immich_search: no`,
   write the no-media manifest (see Output Format) and call `finished_step`.

2. **Discover Immich credentials**:

   ```bash
   env | grep -i immich
   ```

   Look for `IMMICH_URL` (typically `http://localhost:2283`) and `IMMICH_API_KEY`.
   If missing, check `~/.config/immich/` or ask the user.

3. **Run smart search** using the topic keywords from requirements:

   ```bash
   curl -s -X POST "${IMMICH_URL}/api/search/smart" \
     -H "x-api-key: ${IMMICH_API_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"query": "<topic keywords>", "type": "IMAGE", "size": 20}' \
     | jq '.assets.items[] | {id, originalFileName, description: .exifInfo.description}'
   ```

   For location-based searches, add `city` or `country` to the JSON body.
   For people, first resolve person IDs via `/api/people` then add `personIds`.

4. **Select the most relevant assets** — choose images/screenshots that visually
   support the key messages from requirements. Prefer high-resolution assets.

5. **Download selected assets** into the dataroom:

   ```bash
   mkdir -p presentations/<slug>/_dataroom/media
   curl -s "${IMMICH_URL}/api/assets/${ASSET_ID}/original" \
     -H "x-api-key: ${IMMICH_API_KEY}" \
     --output "presentations/<slug>/_dataroom/media/<filename>"
   ```

   Where `<slug>` is the kebab-case presentation topic (e.g.,
   `keystone-infrastructure-overview`).

6. **Write presentation_media_manifest.md** — see Output Format below.

## Output Format

### presentation_media_manifest.md

**When no media search was requested**:

```markdown
# Media manifest

_No media search requested. All image slots will be TODO placeholders._
```

**When media was found**:

```markdown
# Media manifest

| # | Asset ID | Local path | Type | Caption hint | Suggested slide |
|---|----------|------------|------|--------------|-----------------|
| 1 | a1b2c3 | presentations/keystone-overview/_dataroom/media/a1b2c3_rack.jpg | photo | Server rack in the data center | Slide 2: Infrastructure |
| 2 | d4e5f6 | presentations/keystone-overview/_dataroom/media/d4e5f6_terminal.png | screenshot | `ks build` terminal output | Slide 8: Dev workflow |

## Assets not downloaded (TODO)
- [ ] Slide 5: need a photo of a YubiKey — not found in Immich search; add manually
```

## Quality Criteria

- Each listed asset has a valid local path under `presentations/<slug>/_dataroom/media/`
- Each asset has a suggested slide that matches a key message from requirements
- Slots that could not be filled are listed explicitly as TODO items with a
  human-readable description of what is needed
- The manifest is complete even if all slots are TODOs (no silent omissions)

## Context

This step runs after `presentation_gather_requirements` and before `presentation_outline`. The
manifest is used by `presentation_outline` to assign media to specific slides and by
`presentation_build_deck` to embed the correct file paths. Assets downloaded here are
later committed to the notes repo with git LFS in `presentation_deliver`.
