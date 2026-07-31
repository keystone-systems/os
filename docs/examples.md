---
title: Keystone Deployment Examples
description: Server and client deployment examples for various hardware and use cases
---

# Keystone Deployment Examples

This document demonstrates different ways Keystone servers and clients can be deployed and integrated.

## Server Deployment Examples

### Example 1: Home Server

**Hardware**: Raspberry Pi 4 + external USB HDD  
**Services**: VPN, DNS filtering, network storage, automated backups

**Configuration**:

```nix
{
  imports = [ keystone.nixosModules.server ];

  # Network gateway and VPN
  networking.firewall.allowedTCPPorts = [ 51820 ]; # WireGuard

  # ZFS snapshots are managed by sanoid (see os.zfs-backup convention)
}
```

**Use Case**: Home user wants network-wide ad blocking, secure remote access, and centralized backup storage.

### Example 2: Cloud VPS Server

**Hardware**: VPS with 2GB RAM, 50GB storage  
**Services**: VPN endpoint, secure DNS, backup destination

**Configuration**:

```nix
{
  imports = [ keystone.nixosModules.server ];

  # VPN server for remote access
  services.wireguard.enable = true;

  # Secure DNS for clients
  services.unbound.enable = true;

  networking.firewall.allowedTCPPorts = [ 22 51820 ];
}
```

**Use Case**: Always-available external access point for clients, backup destination when away from home.

### Example 3: Dedicated Storage Server

**Hardware**: Mini-ITX server with 4x HDDs  
**Services**: High-capacity storage, media server, backup target

**Configuration**:

```nix
{
  imports = [ keystone.nixosModules.server ];

  # ZFS RAID-Z for redundancy
  boot.supportedFilesystems = [ "zfs" ];

  # Media services
  services.jellyfin.enable = true;
  services.transmission.enable = true;
}
```

**Use Case**: Family media server with redundant storage and automated backups.

## Client Deployment Examples

### Example 1: Developer Workstation

**Hardware**: Desktop/laptop with 16GB+ RAM  
**Features**: Desktop environment, development tools, automated backup to server

**Configuration**:

```nix
{
  imports = [ keystone.nixosModules.client ];

  # Development environment
  environment.systemPackages = with pkgs; [
    vscode git docker nodejs python3
  ];

  # Automated backup to home server
  services.backup.destinations = [ "server.local" ];
}
```

**Integration**: Connects to home server for backups, uses server VPN when remote, accesses shared storage.

### Example 2: Family Laptop

**Hardware**: Standard laptop  
**Features**: Secure desktop environment, automatic backups, web filtering

**Configuration**:

```nix
{
  imports = [ keystone.nixosModules.client ];

  # Family-friendly defaults
  services.parental-controls.enable = true;

  # Uses home server DNS for filtering
  networking.nameservers = [ "192.168.1.1" ];
}
```

**Integration**: Uses home server for network filtering, storage, and backups.

## Integrated Scenarios

### Scenario 1: Mac/Windows User + Linux Server

**Setup**:

- **Server**: Linux server providing network and storage services
- **Client**: Mac/Windows machine connecting to services

**Deployment**:

1. Install Keystone server using ISO on dedicated hardware
2. Configure VPN and file sharing services
3. Connect Mac/Windows clients via WireGuard VPN

**Usage**:

- Remote access to home network through VPN
- Backup Mac/Windows files to Linux server
- Access media and files through web interfaces

### Scenario 2: Full Linux Ecosystem

**Setup**:

- **Server**: Home server providing all services
- **Clients**: Multiple laptops/desktops running Keystone client configuration

**Benefits**:

- Seamless integration between all devices
- Automatic backup and sync
- Shared development environments
- Network-wide security policies

### Scenario 3: Hybrid Cloud + Home Setup

**Setup**:

- **Home Server**: Local services and storage
- **Cloud Server**: VPS for external access
- **Clients**: Devices that connect to both

**Architecture**:

```
[Client] ←→ [Home Server] ←→ Internet ←→ [Cloud Server]
                ↑
           [Other Clients]
```

**Use Case**: Redundant infrastructure with local performance and cloud availability.
