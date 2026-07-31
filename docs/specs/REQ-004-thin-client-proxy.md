# REQ-004: Thin Client Proxy

Enable workstations to host local development servers accessible via the same
hostname from both local connections and remote thin clients over Headscale VPN.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Functional Requirements

### FR-001: Unified Hostname Resolution

- Local connections on the workstation MUST resolve `dev.hostname` to `127.0.0.1`
- Thin clients on the Headscale network MUST resolve `dev.hostname` to the workstation's tailnet IP
- Resolution MUST work without manual `/etc/hosts` configuration on clients

### FR-002: Reverse Proxy

- A reverse proxy MUST run on the workstation to forward requests to local dev servers
- The proxy MUST support multiple simultaneous dev servers (e.g., `app.dev.hostname`, `api.dev.hostname`)
- The proxy MUST support WebSocket connections for hot-reload functionality
- Port mappings (e.g., `app` to `localhost:3000`, `api` to `localhost:8080`) MUST be configurable

### FR-003: TLS Certificates

- The system MUST automatically generate TLS certificates for dev domains
- Certificates MUST be trusted by both local and remote clients
- The system MUST support wildcard certificates (`*.dev.hostname`)
- Certificates MUST integrate with system trust stores

### FR-004: Service Discovery

- The system MAY support automatic detection of running dev servers
- The system MUST support manual registration of port mappings via configuration
- The system SHOULD provide a status dashboard showing active proxied services

### FR-005: Headscale Integration

- The system MUST register DNS records with Headscale MagicDNS
- The system MUST advertise routes if needed for subnet access
- The system MUST handle tailnet reconnection gracefully

## Non-Functional Requirements

### NFR-001: Zero-Configuration Thin Clients

- Thin clients MUST NOT require additional setup beyond Headscale connection
- DNS and certificate trust MUST propagate automatically via tailnet

### NFR-002: Low Latency

- Proxy overhead for local connections MUST be negligible (under 1ms added latency)
- Remote connections MUST only add tailnet transport latency

### NFR-003: Security

- Only tailnet-authenticated clients MUST be able to access proxied services
- Local-only services MAY be excluded from remote access
- The system SHOULD provide audit logging for remote access attempts

### NFR-004: Reliability

- The proxy MUST auto-restart on failure
- The proxy MUST handle dev server restarts gracefully
- The system MUST NOT leave orphaned connections on service changes

## Success Criteria

### SC-001: Developer Workflow

- A developer MUST be able to run `npm run dev` on workstation and access it from thin client within 5 seconds
- The same URL MUST work from both workstation browser and thin client browser
- Hot reload / WebSocket connections MUST work seamlessly
- No manual DNS or hosts file configuration SHALL be required on thin clients
- TLS MUST work without browser warnings on any connected client

## Out of Scope

- Load balancing across multiple workstations
- Service mesh integration
- Production deployment (this is explicitly for dev workflows)
- Non-HTTP protocols (database connections — use direct tailnet IPs)
- Automatic dev server detection via process monitoring
