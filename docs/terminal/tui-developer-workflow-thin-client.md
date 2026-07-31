---
title: Thin Client Development
description: Remote development workflow using mosh, SSH port forwarding, and Zellij session resumption
---

# Thin Client Development

Thin client development transforms any device into a window to your development environment. Your laptop, tablet, or even phone becomes a terminal into a powerful workstation or server where your actual work happens.

## The Concept

Instead of running resource-intensive tools locally:

1. A workstation or server hosts your development environment
2. You connect via terminal from any device
3. Sessions persist on the remote machine
4. Disconnect and reconnect without losing state

Benefits:

- Work from underpowered devices (old laptops, tablets)
- Consistent environment regardless of local machine
- Sessions survive network changes, sleep, even reboots
- Powerful hardware available on demand

## Mosh: Mobile Shell

Mosh (mobile shell) maintains persistent connections that survive network changes, sleep, and roaming between WiFi and cellular.

### How It Differs from SSH

| SSH                               | Mosh                              |
| --------------------------------- | --------------------------------- |
| TCP-based                         | UDP-based                         |
| Connection dies on network change | Survives network changes          |
| Laggy on high-latency links       | Local echo, feels responsive      |
| Requires stable connection        | Handles intermittent connectivity |

### Installation

On NixOS:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.mosh ];

  # Open mosh ports (UDP 60000-61000)
  networking.firewall.allowedUDPPortRanges = [
    { from = 60000; to = 61000; }
  ];
}
```

### Usage

```bash
# Connect to remote host
mosh user@workstation

# Specify SSH port if non-standard
mosh --ssh="ssh -p 2222" user@workstation

# With SSH key
mosh user@workstation -- ssh -i ~/.ssh/id_ed25519
```

### How It Works

1. Mosh initiates an SSH connection to authenticate
2. Starts a mosh-server process on the remote
3. Switches to UDP for the session
4. Local predictions make typing feel instant
5. Connection state survives network changes

Close your laptop on home WiFi, open it at a coffee shop—mosh reconnects automatically.

## SSH Port Forwarding

Access services running on the remote machine as if they were local.

### Local Port Forwarding

Forward a remote port to localhost:

```bash
# Forward remote port 3000 to local port 3000
ssh -L 3000:localhost:3000 user@workstation

# Forward remote PostgreSQL to local
ssh -L 5432:localhost:5432 user@workstation

# Multiple forwards
ssh -L 3000:localhost:3000 -L 5432:localhost:5432 user@workstation
```

Now `localhost:3000` on your laptop reaches the dev server on your workstation.

### SSH Config

Configure persistent forwards in `~/.ssh/config`:

```
Host workstation
    HostName 192.168.1.100
    User developer
    LocalForward 3000 localhost:3000
    LocalForward 5432 localhost:5432
    LocalForward 8080 localhost:8080
```

Then simply:

```bash
ssh workstation
# or
mosh workstation
```

### Dynamic Forwarding (SOCKS Proxy)

Route all traffic through the remote machine:

```bash
ssh -D 1080 user@workstation
```

Configure your browser to use `localhost:1080` as a SOCKS5 proxy. All browsing now happens from the workstation's perspective.

### Combining with Mosh

Mosh doesn't support port forwarding directly. Use SSH for the tunnel, mosh for the session:

```bash
# Terminal 1: SSH tunnel (leave running)
ssh -N -L 3000:localhost:3000 workstation

# Terminal 2: Mosh session
mosh workstation
```

Or use autossh for persistent tunnels:

```bash
autossh -M 0 -N -L 3000:localhost:3000 workstation
```

## Zellij Session Resumption

Zellij sessions persist on the server. This is the key to true thin client development.

### Named Sessions

Create a session per project:

```bash
# On the remote machine
zellij -s project-name
```

### Detaching

Detach without closing:

```bash
# Keyboard shortcut
Ctrl+o then d

# Or from command line
zellij kill-session  # (don't do this, just detach)
```

The session continues running. All your panes, tabs, and running processes remain.

### Reattaching

From any connection:

```bash
# List available sessions
zellij list-sessions

# Attach to specific session
zellij attach project-name

# Attach to last session
zellij attach
```

### Session Management

```bash
# List sessions
zellij list-sessions

# Kill a session (when truly done)
zellij kill-session project-name

# Kill all sessions
zellij kill-all-sessions
```

## Practical Workflow

### Starting Work

```bash
# 1. Connect to workstation
mosh workstation

# 2. Attach to (or create) project session
zellij attach myproject || zellij -s myproject

# 3. You're in your persistent workspace
# All tabs, panes, and running processes are there
```

### During the Day

- Work normally in your Zellij session
- Start dev servers, run tests, edit code
- Everything runs on the remote machine

### Switching Networks

- Close laptop lid (or network drops)
- Open laptop on different network
- Mosh reconnects automatically
- Run `zellij attach` to resume session

### End of Day

```bash
# Option 1: Leave session running
Ctrl+o then d  # Detach from Zellij
exit           # Close mosh connection

# Option 2: Just close the terminal
# Mosh session ends, Zellij session persists
```

Tomorrow, reconnect and attach—everything is exactly as you left it.

## NixOS Configuration

### Workstation/Server Side

```nix
{ pkgs, ... }: {
  # SSH server
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Mosh
  programs.mosh.enable = true;

  # Development tools
  environment.systemPackages = with pkgs; [
    zellij
    helix
    git
    lazygit
    # ... your tools
  ];
}
```

### Client Side (Home Manager)

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    mosh
    autossh
  ];

  programs.ssh = {
    enable = true;
    matchBlocks = {
      workstation = {
        hostname = "workstation.local";
        user = "developer";
        localForwards = [
          { bind.port = 3000; host.address = "localhost"; host.port = 3000; }
          { bind.port = 5432; host.address = "localhost"; host.port = 5432; }
        ];
      };
    };
  };
}
```

## Tips

### Persistent Tunnels with systemd

Create a user service for always-on port forwarding:

```nix
systemd.user.services.workstation-tunnel = {
  Unit.Description = "SSH tunnel to workstation";
  Service = {
    ExecStart = "${pkgs.autossh}/bin/autossh -M 0 -N workstation";
    Restart = "always";
  };
  Install.WantedBy = [ "default.target" ];
};
```

### Wake-on-LAN

Start your workstation remotely:

```bash
# Install wol tool
nix-shell -p wol

# Wake workstation (need MAC address)
wol AA:BB:CC:DD:EE:FF
```

### Clipboard Integration

Use OSC 52 escape sequences for clipboard sync between local and remote. Most modern terminals support this automatically.

## Troubleshooting

### Mosh Won't Connect

```bash
# Check UDP ports are open on server
sudo ufw status
# or
sudo iptables -L -n | grep 60000
```

### Session Not Persisting

Ensure Zellij is running on the _remote_ machine, not locally. The session persists where Zellij runs.

### Port Forward Not Working

```bash
# Check if port is already in use locally
lsof -i :3000

# Verify SSH connection includes the forward
ssh -v workstation 2>&1 | grep "Local forward"
```
