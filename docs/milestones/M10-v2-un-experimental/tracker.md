# v2 milestone tracker

Snapshot of [milestone/10](https://github.com/ncrmro/keystone/milestone/10) as
of 2026-06-06. Refresh with:

```bash
gh issue list --repo ncrmro/keystone --milestone "v2 — Un-experimental" \
  --state all --limit 60 \
  --json number,title,state \
  --jq 'sort_by(.state, -.number) | .[] |
        "- [\(if .state == "CLOSED" then "x" else " " end)] #\(.number) — \(.title)"'
```

There is no single release-tracker issue yet; if you open one, update
`README.md` frontmatter `trackerIssue:` field and embed the body in place of the list below.

## Issues

- [x] #454 — chore(keystone): codify keystone.systemFlake pointer path as single source of truth
- [ ] #515 — audit codebase for complicated vs complex code (v2)
- [ ] #476 — fix(agents-e2e): smoke harness should pause/resume the agent's task-loop timer itself
- [ ] #475 — fix(agents): clean up orphan agent ~/.keystone and ~/notes/.deepwork dirs; add ks doctor check that DEEPWORK_ADDITIONAL_JOBS_FOLDERS matches active system
- [ ] #469 — feat(os): reconcile ZFS home datasets on activation
- [ ] #458 — feat(test): multi-node fleet VM test harness with headscale mesh and ZFS replication over tailnet
- [ ] #446 — epic(arm): ARM-ecosystem support
- [ ] #445 — feat(testing): aarch64 VM harness for fast installer and ARM-host iteration
- [ ] #444 — feat(arm): run keystone.server on aarch64 (Pi 5 / CM4 NAS)
- [ ] #443 — feat(installer): aarch64 Pi SD installer parity with x86 ISO
- [ ] #371 — OS agents should use remote host MCP servers when launched by a human user
- [ ] #345 — feat(agents): resolve the agent identity model and cross-tool `--agent` surfaces
- [ ] #291 — test(agents): add e2e test for agent task loop pipeline
- [ ] #219 — fix(agents): repair agentctl sourcing of hm-session-vars under nounset
- [ ] #90 — Allow using other agents in os agent tasks
