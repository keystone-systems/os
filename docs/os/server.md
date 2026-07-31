---
title: Server Module
description: Unified nginx reverse proxy, ACME wildcard certificates, and DNS record generation
---

# Server Module (`keystone.server`)

The server module provides unified nginx reverse proxy, ACME wildcard certificates, and DNS record generation for self-hosted services.

## Quick Start

```nix
keystone.server = {
  enable = true;
  domain = "example.com";
  tailscaleIP = "100.64.0.6";
  acme = {
    enable = true;
    credentialsFile = config.age.secrets.cloudflare-api-token.path;
  };
  services = {
    immich.enable = true;      # -> photos.example.com
    vaultwarden.enable = true; # -> vaultwarden.example.com
    forgejo.enable = true;     # -> git.example.com
  };
};
```

## Architecture

### How It Works

1. **Service Registration**: Each `keystone.server.services.<name>.enable = true` registers the service
2. **Nginx Generation**: The nginx module auto-generates virtualHosts with SSL and access control
3. **ACME Certificates**: Wildcard certificate via Cloudflare DNS-01 challenge
4. **DNS Records**: Auto-generated for headscale integration

### Module Structure

```
modules/server/
├── default.nix          # Main module with imports and port conflict detection
├── lib.nix              # Shared helpers (mkServiceOptions, accessPresets)
├── acme.nix             # ACME wildcard cert configuration
├── nginx.nix            # Base nginx config + virtualHost generation
├── dns.nix              # DNS record generation for headscale
├── services/            # Individual service modules
│   ├── immich.nix
│   ├── vaultwarden.nix
│   └── ...
└── headscale/
    └── dns-import.nix   # Consume DNS records on headscale host
```

## Available Services

| Service     | Subdomain    | Port | Default Access    | Notes              |
| ----------- | ------------ | ---- | ----------------- | ------------------ |
| immich      | photos       | 2283 | tailscale         | maxBodySize=50G    |
| vaultwarden | vaultwarden  | 8222 | tailscale         |                    |
| forgejo     | git          | 3001 | tailscale         |                    |
| grafana     | grafana      | 3002 | tailscale         |                    |
| prometheus  | prometheus   | 9090 | tailscale         |                    |
| loki        | loki         | 3100 | tailscale         |                    |
| headscale   | mercury      | 8080 | **public**        | VPN control server |
| miniflux    | miniflux     | 8070 | tailscale         |                    |
| harmonia    | harmonia     | 5000 | tailscale         | Nix binary cache   |
| mail        | mail         | 8082 | tailscale         | Stalwart admin     |
| adguard     | adguard.home | 3000 | tailscaleAndLocal | DNS admin          |

## Configuration Reference

### Top-Level Options

```nix
keystone.server = {
  enable = true;                    # Enable server module
  domain = "example.com";           # Base domain for all services
  tailscaleIP = "100.64.0.6";       # Tailscale IP for DNS records
};
```

### ACME Configuration

```nix
keystone.server.acme = {
  enable = true;                    # Enable wildcard certificate (default: false)
  email = "admin@example.com";      # ACME account email (default: admin@<domain>)
  credentialsFile = "/run/agenix/cloudflare-api-token";
  extraDomainNames = [              # Additional domains in cert
    "*.home.example.com"
  ];
};
```

**Cloudflare API Token Secret** (agenix example):

```nix
# In your host configuration
age.secrets.cloudflare-api-token = {
  file = "${inputs.agenix-secrets}/secrets/cloudflare-api-token.age";
  owner = "acme";
  group = "acme";
};

# Secret file content:
# CLOUDFLARE_DNS_API_TOKEN=your_token_here
```

### Per-Service Options

Each service supports these options:

```nix
keystone.server.services.immich = {
  enable = true;                    # Enable the service
  subdomain = "photos";             # Subdomain (photos.example.com)
  port = 2283;                      # Backend port
  access = "tailscale";             # Access control preset
  maxBodySize = "50G";              # nginx client_max_body_size
  websockets = true;                # Enable WebSocket proxying
  registerDNS = true;               # Include in DNS records
};
```

## Access Control Presets

| Preset              | Description        | Allowed Networks                   |
| ------------------- | ------------------ | ---------------------------------- |
| `tailscale`         | Tailscale VPN only | 100.64.0.0/10, fd7a:115c:a1e0::/48 |
| `tailscaleAndLocal` | Tailscale + LAN    | Above + 192.168.1.0/24             |
| `public`            | No restrictions    | All                                |
| `local`             | LAN only           | 192.168.1.0/24                     |

## DNS Integration with Headscale

### On the Server Host

DNS records are automatically generated:

```nix
# This is set automatically based on enabled services
keystone.server.generatedDNSRecords = [
  { name = "photos.example.com"; type = "A"; value = "100.64.0.6"; }
  { name = "vaultwarden.example.com"; type = "A"; value = "100.64.0.6"; }
  # ...
];
```

### On the Headscale Host

Import DNS records from all server hosts:

```nix
keystone.headscale = {
  enable = true;
  dnsRecords =
    oceanConfig.keystone.server.generatedDNSRecords
    ++ mercuryConfig.keystone.server.generatedDNSRecords;
  extraRecords = [
    # Manual additional records
    { name = "custom.example.com"; type = "A"; value = "100.64.0.99"; }
  ];
};
```

## Complete Example

### Server Host (Ocean)

```nix
{ config, inputs, ... }:
{
  # Cloudflare API token for ACME
  age.secrets.cloudflare-api-token = {
    file = "${inputs.agenix-secrets}/secrets/cloudflare-api-token.age";
    owner = "acme";
    group = "acme";
  };

  keystone.server = {
    enable = true;
    domain = "ncrmro.com";
    tailscaleIP = "100.64.0.6";
    acme = {
      enable = true;
      credentialsFile = config.age.secrets.cloudflare-api-token.path;
      extraDomainNames = [ "*.home.ncrmro.com" ];
    };
    services = {
      immich.enable = true;
      vaultwarden.enable = true;
      forgejo.enable = true;
      grafana.enable = true;
      prometheus.enable = true;
      loki.enable = true;
      miniflux.enable = true;
      harmonia.enable = true;
      mail.enable = true;
      adguard.enable = true;
    };
  };

  # Actual service configurations (unchanged)
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    mediaLocation = "/ocean/media/photos";
  };

  services.vaultwarden = {
    enable = true;
    config.ROCKET_PORT = 8222;
  };
}
```

### Headscale Host (Mercury)

```nix
{ config, inputs, ... }:
let
  # Reference ocean's configuration for DNS records
  oceanConfig = inputs.self.nixosConfigurations.ocean.config;
in
{
  keystone.server = {
    enable = true;
    domain = "ncrmro.com";
    tailscaleIP = "100.64.0.38";
    acme = {
      enable = true;
      credentialsFile = config.age.secrets.cloudflare-api-token.path;
    };
    services = {
      headscale.enable = true;
      adguard = {
        enable = true;
        subdomain = "adguard.mercury";
      };
    };
  };

  # Import DNS records from ocean
  keystone.headscale = {
    enable = true;
    dnsRecords = oceanConfig.keystone.server.generatedDNSRecords;
  };
}
```

## Adding New Services

1. Create `modules/server/services/<name>.nix`:

```nix
{ lib, config, ... }:
let
  serverLib = import ../lib.nix { inherit lib; };
  serverCfg = config.keystone.server;
  cfg = serverCfg.services.myservice;
in {
  options.keystone.server.services.myservice = serverLib.mkServiceOptions {
    description = "My Service description";
    subdomain = "myservice";
    port = 8080;
    access = "tailscale";
    websockets = true;
    registerDNS = true;
  };

  config = lib.mkIf (serverCfg.enable && cfg.enable) {
    keystone.server._enabledServices.myservice = {
      inherit (cfg) subdomain port access maxBodySize websockets registerDNS;
    };
  };
}
```

2. Import in `modules/server/default.nix`:

```nix
imports = [
  # ... existing imports
  ./services/myservice.nix
];
```

## Port Conflict Detection

The module automatically detects port conflicts. If two enabled services use the same port, an assertion fails:

```
error: keystone.server: Port conflict detected among enabled services.
port 8080 used by: service1, service2
```

## Legacy Modules

These modules are still available but only configure the service itself (no nginx/DNS):

- `keystone.server.binaryCache` - Harmonia with signing keys
- `keystone.server.monitoring` - Prometheus/Grafana stack
- `keystone.server.vpn` - Headscale (Kubernetes-based)

The consumer is responsible for nginx/TLS/access control when using legacy modules.

## Troubleshooting

### ACME Certificate Issues

```bash
# Check ACME status
systemctl status acme-wildcard-example-com.service

# Force certificate renewal
systemctl start acme-wildcard-example-com.service

# Check certificate
openssl s_client -connect photos.example.com:443 -servername photos.example.com
```

### Nginx Issues

```bash
# Test nginx configuration
nginx -t

# Check nginx status
systemctl status nginx

# View access logs
journalctl -u nginx -f
```

### DNS Not Resolving

1. Verify tailscaleIP is set correctly
2. Check headscale has imported the DNS records
3. Verify headscale service is running: `systemctl status headscale`
4. Check client DNS: `tailscale status --peers`
