# Remote machine debug

Use this skill when a bug or verification step must be checked on a real remote
host over SSH, especially when the host has a live desktop session and the
result needs a screenshot from that host rather than from the local machine.

## Goals

- Prove whether the blocker is reachability, SSH auth, sudo, deployment state,
  or the feature itself.
- Run the exact command under test on the remote machine without leaking the
  password into shell history or screenshots.
- Capture screenshots from the remote compositor, not from the local workstation.

## Core rules

- Start by forcing a single SSH identity with `-i` and `IdentitiesOnly=yes`.
  Do not guess through agent-loaded keys.
- Separate network failure from auth failure before debugging the application.
- Save command output to a transcript first. Screenshot the transcript window
  second.
- If the remote machine is locked, unlock it before capturing. A remote `grim`
  against a locked Hyprland session will capture `hyprlock`, not the terminal.
- When validating a new CLI that is not yet deployed on the remote machine, run
  the exact built artifact or Nix store path instead of assuming the installed
  system package is current.

## Workflow

### 1. Confirm reachability and the right SSH key

Use explicit probes:

```bash
ping -c 2 -W 1 <ip>
ssh -4 -i ~/.ssh/<key> \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  <user>@<ip> 'hostname && whoami && command -v ks'
```

Interpret the result before going further:

- `No route to host` / timeouts: network or host state problem.
- `Permission denied (publickey)`: wrong key or remote authorized-keys state.
- Successful login but missing subcommand: remote deployment is old; test the
  new artifact directly.

### 2. Run privileged verification without exposing the password

Prefer this pattern:

```bash
printf '<password>\n' | sudo -S -p '' <command>
```

For example:

```bash
ssh -4 -i ~/.ssh/<key> \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  <user>@<ip> '
    KS=/nix/store/<store-path>/bin/ks
    printf "\n== ks hardware report --json ==\n\n"
    printf "<password>\n" | sudo -S -p "" "$KS" hardware report --json
    printf "\n\n== ks hardware setup --dry-run ==\n\n"
    printf "<password>\n" | sudo -S -p "" "$KS" hardware setup --dry-run || true
  ' | tee /tmp/remote-verification.txt
```

This keeps the password out of the screenshot while preserving the full output
for later review.

### 3. If the remote `ks` is too old, test the exact new build

Do not assume the installed profile has the new subcommand. Check:

```bash
ssh <user>@<ip> 'readlink -f $(command -v ks) && ks --version || true'
```

If needed, build locally and copy the exact store path:

```bash
nix build .#ks --print-out-paths
export NIX_SSHOPTS='-i /home/<local-user>/.ssh/<key> -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
nix copy --no-check-sigs --to ssh-ng://<user>@<ip> /nix/store/<store-path>-ks-<version>
```

Then run:

```bash
ssh <user>@<ip> '/nix/store/<store-path>-ks-<version>/bin/ks hardware --help'
```

### 4. Inspect the remote graphical session before screenshot work

Check that the remote user session is real and that Wayland variables exist:

```bash
ssh <user>@<ip> 'loginctl list-sessions --no-legend'
ssh <user>@<ip> 'systemctl --user show-environment | rg "^(WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR|HYPRLAND_INSTANCE_SIGNATURE)=" || true'
ssh <user>@<ip> 'command -v grim || true; command -v hyprctl || true; command -v ghostty || true'
```

If there is no live session environment, remote compositor screenshots will not
work yet.

### 5. If the screen is locked, unlock it first

Check for `hyprlock`:

```bash
ssh <user>@<ip> 'pgrep -af hyprlock || true'
```

If input injection is not already installed, use a temporary Nix shell:

```bash
ssh <user>@<ip> '
  export XDG_RUNTIME_DIR=/run/user/1000
  export WAYLAND_DISPLAY=wayland-1
  export DISPLAY=:0
  export HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | sed -n "s/^HYPRLAND_INSTANCE_SIGNATURE=//p")
  nix shell nixpkgs#wtype -c sh -lc '\''wtype <password> && wtype -k Return'\''
'
```

Verify the session is no longer sitting on `hyprlock` before capturing.

### 6. Put the transcript on the remote screen

Copy the saved transcript to the remote machine:

```bash
scp -i ~/.ssh/<key> /tmp/remote-verification.txt <user>@<ip>:/tmp/remote-verification.txt
```

Create a short-lived helper script:

```bash
cat >/tmp/remote-window.sh <<'EOF'
#!/usr/bin/env bash
clear
cat /tmp/remote-verification.txt
printf "\n"
sleep 60
EOF
chmod +x /tmp/remote-window.sh
```

Launch it inside the live session:

```bash
ssh <user>@<ip> '
  export XDG_RUNTIME_DIR=/run/user/1000
  export WAYLAND_DISPLAY=wayland-1
  export DISPLAY=:0
  export HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | sed -n "s/^HYPRLAND_INSTANCE_SIGNATURE=//p")
  hyprctl dispatch exec "ghostty -e /tmp/remote-window.sh"
'
```

### 7. Capture from the remote compositor

Do not use local `grim` for this. Capture on the remote machine:

```bash
ssh <user>@<ip> '
  export XDG_RUNTIME_DIR=/run/user/1000
  export WAYLAND_DISPLAY=wayland-1
  export DISPLAY=:0
  export HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | sed -n "s/^HYPRLAND_INSTANCE_SIGNATURE=//p")
  sleep 3
  hyprctl dispatch fullscreen 1
  sleep 2
  grim /tmp/remote-capture.png
  hyprctl -j activewindow | jq ".class, .title, .fullscreen"
'
```

Validate the active window metadata. A good capture should report the expected
terminal class and helper script title, not `hyprlock`.

### 8. Pull the PNG back and inspect it locally

```bash
scp -i ~/.ssh/<key> <user>@<ip>:/tmp/remote-capture.png ~/Pictures/remote-capture.png
```

Inspect it locally before cleanup. If it shows the wrong surface, repeat the
unlock and capture steps instead of assuming the file is correct.

### 9. Clean up

```bash
ssh <user>@<ip> 'rm -f /tmp/remote-window.sh /tmp/remote-verification.txt /tmp/remote-capture.png'
```

## Common failure modes

### Wrong machine or wrong screenshot source

Symptom: the PNG shows the local workstation instead of the remote host.

Fix: run `grim` on the remote machine inside its own Wayland session, then copy
the file back with `scp`.

### Lock screen captured instead of terminal

Symptom: the PNG shows `hyprlock`.

Fix: unlock first, verify `hyprlock` is gone, reopen the transcript window, and
capture again immediately.

### Remote CLI is missing the subcommand

Symptom: `ks` exists, but `ks hardware` is unknown.

Fix: check the consumer flake pin and test the PR build directly from an
explicit Nix store path until the remote system is updated.
