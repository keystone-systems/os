---
title: SSH Agent
description: SSH key management via systemd user service for terminal and desktop sessions
---

# SSH Agent

Keystone runs `ssh-agent` as a systemd user service, providing SSH key
management for terminal and desktop sessions.

## How It Works

Three pieces work together:

1. **`services.ssh-agent`** (home-manager) - Starts a systemd user service running `ssh-agent -D -a $XDG_RUNTIME_DIR/ssh-agent`
2. **Session environment** - Exposes `SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent` so terminal shells, editors, and desktop applications inherit it
3. **`programs.ssh.addKeysToAgent = "yes"`** - On first SSH use, the key is automatically added to the agent after you enter the passphrase

## Passphrase-Protected Keys

With `AddKeysToAgent yes` in SSH config:

1. First `git push` or `ssh` of the session prompts for your key passphrase
2. The key is cached in the agent for the rest of the session
3. Subsequent operations use the cached key without prompting

No PAM integration or GNOME Keyring needed.

## Git SSH Commit Signing

If you use `gpg.format = "ssh"` for Git commit signing, it works automatically since `ssh-agent` provides the signing key via `SSH_AUTH_SOCK`. No additional configuration required.

## Coexistence with Hardware Keys

The desktop module may also include a hardware-key module that uses GPG agent for SSH. Both can coexist:

- **ssh-agent**: Handles standard SSH keys (`~/.ssh/id_ed25519`, etc.)
- **GPG agent**: Handles hardware security keys (YubiKey, etc.) when configured

If you use a hardware key exclusively, the ssh-agent service still runs but remains idle.

## Verification

After logging in to your session:

```bash
# Check the socket exists
echo $SSH_AUTH_SOCK
# Expected: /run/user/1000/ssh-agent

# Check the agent is running
ssh-add -l
# Expected: "The agent has no identities." (not "Could not open connection")

# Check the systemd service
systemctl --user status ssh-agent
# Expected: active (running)
```

## Troubleshooting

### "Could not open a connection to your authentication agent"

The agent service may not be running:

```bash
systemctl --user start ssh-agent
systemctl --user status ssh-agent
```

### SSH_AUTH_SOCK is empty or wrong

Check that your session inherited the environment variable:

```bash
# Should show the ssh-agent socket path
hyprctl getoption env

# If missing in a desktop session, the env line may not be in hyprland.conf
grep SSH_AUTH_SOCK ~/.config/hypr/hyprland.conf
```

### Key not being cached after entering passphrase

Verify `AddKeysToAgent` is set:

```bash
ssh -G github.com | grep addkeystoagent
# Expected: addkeystoagent yes
```
