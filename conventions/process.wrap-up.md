# Convention: Session wrap-up (process.wrap-up)

A human-facing tool for winding down engineering work when there are too many open
threads. Use `/wrap-up` to distill in-flight context into durable artifacts — notes,
issue comments, and PR check-ins — so work can be set down cleanly and resumed later
by another agent or human.

This is not an agent operational convention. It is intentionally invoked by the human
when switching out of engineering mode.

## When to wrap up

1. Humans SHOULD run `/wrap-up` when they have too many open threads and need to step
   back from engineering work.
2. Humans SHOULD run `/wrap-up` before handing off work to another person or agent.
3. Use `/wrap-up defer <reason>` to explicitly record why work is being set aside and
   what condition should trigger picking it back up.

## What wrap-up produces

Every wrap-up MUST produce at minimum:

- A `reports/` note in `~/notes` capturing context, status, testing, next steps,
  and deferred items.
- A structured handoff comment on every open issue or PR that was touched during the session.

When no tracking issue exists for in-flight work, wrap-up MUST create one and link it
to an appropriate milestone before commenting.

## Report note requirements

4. The report MUST be created non-interactively in `reports/` using `zk`:

   ```bash
   zk --notebook-dir ~/notes new reports/ \
     --title "Wrap-up: <short description> $(date +%Y-%m-%d)" \
     --no-input --print-path \
     --extra report_kind="session-wrap-up" \
     --extra source_ref="wrap-up-skill"
   ```

5. Before creating a new report, agents MUST search for a prior wrap-up of the same scope:

   ```bash
   zk --notebook-dir ~/notes list reports/ \
     --tag "report/session-wrap-up" --sort created- --limit 1 --format json
   ```

6. If a prior report exists, the new note MUST set `previous_report` in frontmatter.
7. The report body MUST include these sections in order:
   - **Context** — what was being worked on, key decisions, relevant refs (SHAs, branches, files).
   - **Status** — what is complete, in progress, and blocked.
   - **Testing** — commands run and outcomes, or an explicit statement that no testing occurred.
   - **Next steps** — ordered concrete actions for the next agent or human (name files, commands, issue numbers).
   - **Deferred** — items explicitly punted with the reason and a suggested trigger for revisiting.

## Issue and PR comment requirements

8. Agents MUST post a handoff comment to every open issue or PR touched in the session.
9. The comment header MUST be `## Session check-in — <YYYY-MM-DD>` for normal wrap-ups
   or `## Deferred — <YYYY-MM-DD>` for deferred wrap-ups.
10. Every comment MUST include these subsections: **What happened**, **Testing**,
    **Next steps**, and **Deferred** (or "nothing deferred").
11. The comment MUST end with a footer identifying it as a wrap-up check-in and linking
    the report note path or URL.

## Tracking issue creation

12. When no tracking issue exists for in-flight work, agents MUST create one before
    commenting. The issue title MUST be concise and follow Conventional Commits style.
13. The new issue MUST be linked to an existing milestone. If no suitable milestone
    exists, agents MUST ask the user before creating one.
14. The issue ref MUST be recorded in the report note frontmatter using the canonical
    format: `gh:<owner>/<repo>#<number>` or `fj:<owner>/<repo>#<number>`.

## Project linkage

15. Wrap-up MUST NOT update the project hub note just to record a session check-in,
    report, or tracking issue.
16. Instead, the report note and any created tracking issue MUST carry the project
    linkage directly through canonical refs such as `repo_ref`, `milestone_ref`,
    and `issue_ref`, plus the appropriate project or repo tags.
17. If a project hub note is already in scope for unrelated substantive work, it MAY
    be updated as part of that separate work, but wrap-up itself MUST NOT treat hub
    mutation as a required or default step.

## Completion

18. Wrap-up is complete when the agent has:
    - Confirmed the report note path.
    - Listed every issue/PR that received a comment with its URL.
    - Noted any step that failed and the manual fallback.
