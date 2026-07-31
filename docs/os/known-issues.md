---
title: Known Issues
description: Known issues and workarounds in Keystone
---

# Known Issues

## Zellij: `rename-tab` Targets Wrong Tab with Multiple Clients

**Affects**: `zellij action rename-tab` when multiple clients are attached to the same session

**Symptom**: Running `zellij action rename-tab "name"` renames the other client's focused tab instead of yours.

**Cause**: This is a [confirmed architectural limitation](https://github.com/zellij-org/zellij/pull/3747). CLI actions create a temporary "fake client" connection to the server socket. The fake client has no real focused tab, so the server resolves focus from another connected client.

As maintainer imsnif stated:

> "The CLI is not aware of multiple clients and can never be (because multiple clients being focused on the terminal is a Zellij concept)."

**Related issues**:

- [zellij#4591](https://github.com/zellij-org/zellij/issues/4591) — rename panes/tabs by index
- [zellij#4602](https://github.com/zellij-org/zellij/issues/4602) — rename specific tab by ID
- [zellij#3728](https://github.com/zellij-org/zellij/issues/3728) — NewTab + RenameTab renames wrong tab

**Workaround**: Use the [zellij-tab-name](https://github.com/Cynary/zellij-tab-name) plugin, which uses `$ZELLIJ_PANE_ID` to correctly identify the calling client's tab:

```bash
echo '{"pane_id": "'"$ZELLIJ_PANE_ID"'", "name": "my-tab"}' | zellij pipe --name change-tab-name
```

Keystone now uses this plugin-backed approach for `ztab` and default tab naming. Raw
`zellij action rename-tab ...` still has the multi-client limitation.
