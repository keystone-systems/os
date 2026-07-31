---
title: Keystone Hybrid Architecture
description: Understanding the flexible architecture of Keystone Clusters
---

# Keystone Hybrid Architecture

Keystone Systems offers a unified architecture that spans bare metal, private data centers, and public clouds. Whether you choose our Managed Services or run Self-Hosted, the fundamental building blocks remain consistent.

## The Control Plane

The Control Plane is the brain of the Kubernetes cluster (API Server, Scheduler, Controller Manager, Etcd).

### Option A: Self-Hosted (Primer Servers)

For complete independence and air-gapped environments.

- **Bootstrap:** Uses [Primer Servers](cluster-primer.md) to establish the initial Root of Trust and Etcd quorum.
- **Location:** Runs on dedicated hardware or VMs within your own network.
- **Pros:** Total control, works without internet, data never leaves the building.

### Option B: Managed Services

For reduced operational overhead.

- **Bootstrap:** Instant provisioning via the Keystone Console.
- **Location:** Hosted in Keystone's secure multi-tenant cloud.
- **Pros:** 99.99% SLA, automated backups, zero maintenance, lower hardware footprint on-prem.

## The Data Plane (Worker Nodes)

Worker nodes execute your containerized workloads. In Keystone's architecture, workers are highly flexible:

1.  **Universal Join:** A worker node can be any Linux machine that meets the minimum requirements. It simply needs to run the Keystone agent and have network reachability (direct or tunneled) to the control plane.
2.  **Mixed Fleet:** A single cluster can contain:
    - High-performance bare metal servers (e.g., for databases).
    - Virtual Machines (e.g., internal VMWare/Proxmox fleet).
    - Cloud Instances (e.g., AWS EC2 Spot instances for batch processing).

## Network Topology

### Overlay Networking

We use **Cilium** as the CNI (Container Network Interface) to provide a flat, secure Layer 3 network across all nodes, regardless of their physical location.

- **Pod-to-Pod Communication:** Encapsulated (VXLAN/Geneve) or native routing.
- **Encryption:** Transparent WireGuard encryption for all traffic traversing untrusted networks (e.g., between on-prem and cloud).

### Connectivity Models

**Model 1: Direct Connect (Standard Enterprise)**

- Control Plane and Workers share a private routable network (VLAN, VPN Site-to-Site, or AWS Direct Connect).
- Lowest latency.

**Model 2: The "Satellite" Model (Edge/IoT)**

- Workers are distributed behind various NATs (cafes, cell towers, home offices).
- Workers initiate an outbound persistent tunnel to the Control Plane.
- Ideal for Managed Services and Edge Computing.

## Storage Architecture

Keystone leverages **ZFS** and modern CSI (Container Storage Interface) drivers to handle storage in hybrid environments.

- **Local Storage:** High-performance NVMe backed by ZFS for databases.
- **Replicated Storage:** Mayastor or Longhorn for replicating volumes across nodes.
- **Cloud Storage:** Direct integration with AWS EBS/EFS when running on cloud nodes.
- **Distributed & Object Storage:** Ceph for highly scalable block, file, and object storage across your cluster.
