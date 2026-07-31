# Output Format Rules

These rules apply to all role outputs unless a role explicitly overrides them.

- Output MUST be valid Markdown.
- Structured sections MUST use H2 (`##`) headers.
- Lists MUST use `-` (not `*` or `+`).
- Code blocks MUST specify a language identifier (e.g., ` ```typescript `).
- Output SHOULD NOT include preamble ("Sure, here is...") or sign-off ("Let me know if...").
- When a verdict or decision is required, it MUST appear as the **first line** of output, not buried in prose.
- Filenames and paths MUST be formatted as inline code (`` `path/to/file` ``).
- When referencing source locations, use `file_path:line_number` format.
- Tables SHOULD be used for structured comparisons (3+ items with 2+ attributes).
- Output MUST NOT contain emojis unless the requesting context explicitly allows them.
- All output MUST be succinct. Prefer structured formats (bullets, tables, headers) over verbose prose. Avoid redundancy and filler.
- Code comments MUST be nuanced explanations of _why_ — not _what_. Comments MUST be succinct: one line for inline, a short block for file-level context. Never restate what the code already says.
