# Code comments

Comments explain **why**, not what. Use prefixes for special cases: `SECURITY:` names the specific attack vector mitigated, `CRITICAL:` flags a cross-module invariant that breaks silently if violated, `TODO:` states the consequence of leaving the gap.

Don't reference the current PR, fix, or session in source comments (`PR #X`, "the bug we just fixed", "what Copilot flagged"). That context belongs in commit messages and PR descriptions, which travel with the change. Source comments outlive their PR — references rot.

Don't pre-emptively document trade-offs you didn't take. Defending a decision against an imaginary reviewer in a paragraph block is clutter; if a real reviewer pushes back, address it in the PR conversation. Non-obvious decisions get one sentence; obvious ones get nothing.
