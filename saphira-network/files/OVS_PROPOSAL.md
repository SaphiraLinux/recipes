# OVS Proposal — saphira-network simple OVS command family

Status: proposal / roadmap (nothing implemented beyond `ovs-vmswitch`).
License: BSL 1.1. Target: SaphiraD (systemd-networkd) first, but every command
works on any systemd host with Open vSwitch — not just Saphira. We are
openers of gates, not gatekeepers.

## Goal

Wrap the ovs-vsctl / ovs-dpctl surface into a handful of memorable
do-one-thing commands, so a person who sees the list once can drive a
switch from memory. Everything is scriptable, everything is reversible,
nothing requires a dashboard. A web interface, if it ever exists, is a
last resort for simple management — the commands are the product.

## The command set (target: ~10 verbs)

    ovs-bridge   add|del|list NAME [--remote HOST] [--mtu N]
    ovs-port     add|del|list BRIDGE PORT [--internal] [--vlan N] [--remote HOST]
    ovs-uplink   add BRIDGE NIC [--clone-mac] [--remote HOST]
                 del BRIDGE NIC [--remote HOST]
    ovs-bond     add BRIDGE PORT NIC... [--mode slb|lacp] [--remote HOST]
                 del BRIDGE PORT [--remote HOST]
    ovs-vlan     add|del BRIDGE PORT VLAN [--remote HOST]
    ovs-tunnel   add BRIDGE NAME vxlan|gre REMOTE_IP [--key N] [--remote HOST]
                 del BRIDGE NAME [--remote HOST]
    ovs-patch    add BRIDGE-A PORT-A BRIDGE-B PORT-B [--remote HOST...]
    ovs-net      add|del|list NAME BRIDGE [--ipv4 CIDR] [--ipv6 CIDR]
                 (the existing ovs-vmswitch behaviour: libvirt network +
                 systemd-networkd configs, as one do-task)
    ovs-status   [bridge|port|nic|tunnel]
    ovs-rollback TIMEOUT

Mapping to ovs-vsctl (phase 1 uses only this surface):

    ovs-bridge add     -> add-br NAME (+ fail_mode=standalone, rstp/fstp off
                          by default, other_config:hwaddr when --clone-mac)
    ovs-port add       -> add-port BRIDGE PORT (+ trunks / tag=VLAN)
    ovs-port --internal-> add-port + set Interface PORT type=internal
    ovs-uplink add     -> pre-flight checks, then add-port BRIDGE NIC
                          (+ MAC clone: copy NIC hwaddr onto the bridge
                          internal/bridge port so external ARP state and
                          DHCP leases survive the move)
    ovs-bond add       -> add-bond BRIDGE PORT NIC... with
                          lacp=active + bond_mode=lacp (when --mode lacp)
                          or bond_mode=balance-slb (default: no switch
                          cooperation required)
    ovs-tunnel add     -> add-port BRIDGE NAME + set Interface NAME
                          type=vxlan|gre options:remote_ip=REMOTE_IP
                          (+ options:key=N when --key given)
    ovs-patch add      -> two Interfaces type=patch with peer= each other
                          (local switches); cross-host patches are a
                          tunnel pair under the hood (phase 3)
    ovs-net            -> the ovs-vmswitch transaction (bridge + internal
                          port + networkd configs + libvirt XML) refactored
                          onto the same building blocks

## Safety model (every mutating command)

1. Pre-flight, refuse instead of warn where data would be lost:
   - the NIC is not already enslaved (bridge/bond/OVS port), and
   - no systemd-networkd .network/.netdev file currently matches the
     device (we check /etc/systemd/network and networkctl), and
   - the target bridge/port does not already exist.
2. Ask: "device NIC will be moved into BRIDGE; links on it will drop for
   ~1-2s and any networkd config for it stops applying. Continue?"
3. Apply, then arm a rollback timer: after N seconds (default 30,
   `--rollback-timeout`, 0 disables) the command health-checks local
   reachability (a detached subshell pings the host's own management
   path / waits for operator ACK); on failure it restores the previous
   OVS database snapshot and the previous networkd files automatically.
4. State of intent is written to /etc/ovs/switches.d/*.conf BEFORE
   anything is applied: every bridge, port, uplink, bond, tunnel and its
   options. This file is the rollback source and the regeneration input
   (networkd configs and OVS rows are reproducible from it).

## Remote model (--remote HOST)

`--remote HOST` wraps every ovs-* call in `ssh root@HOST -- saphira-ovs ...`
(same command grammar on both ends; the remote side is the same package).
Phase 1: plain ssh, key-based. Later: an ssh ControlMaster multiplexed
session per host so multi-host operations (mesh tunnels, patch cables)
run as one logical transaction. Nothing remote requires Saphira — any
systemd host with our package (or even just ovs-vsctl present) works.

## Aggregation beyond LACP (the 4x10GbE + 40GbE case)

LACP aggregates per-copper and needs a cooperating partner switch. OVS
`balance-slb` bonds do source-load-balancing per flow without switch
cooperation, so 4x10GbE on one host can genuinely saturate a 40GbE peer
when the peer is another OVS host running the same bond. This is phase 4:
`ovs-bond add --mode slb` on both ends, plus per-flow hashing (recirculation
buckets) tuning. VPN-bridged bonds (phase 5) extend the same idea across
encrypted transports.

## Isolation (later phase)

"this switch port can talk to that switch port and nothing else" =
per-port isolation (`other_config:isolated=true` on ports sharing a
bridge) + VLAN pairs or explicit allow-flows via ovs-ofctl. Exposed as
`ovs-port add --isolate-with PORT` once the base set is proven.

## Phases

1. **vsctl local** — ovs-bridge, ovs-port (--internal), ovs-uplink
   (--clone-mac), ovs-net refactor, ovs-status. Safety model + persistence
   from day one.
2. **remote** — `--remote HOST` on every command; ssh transport.
3. **rollback hardening** — OVS DB snapshot/restore + networkd file
   restore + detached watchdog timer on every mutating command.
4. **bonds** — ovs-bond with slb default, lacp optional; the 4x10GbE
   story.
5. **tunnels + patches** — ovs-tunnel (vxlan/gre), ovs-patch, mesh
   auto-join between named hosts. LAB-PROVEN on the 3-node overlay
   (nodea/b/c): a full vxlan triangle between three bridges is an L2
   cycle - without STP it broadcast-storms (2k+ pkt/s on an idle bridge).
   Any bridge that gains a second tunnel/link MUST set stp_enable=true
   (ovs-tunnel will do this automatically once a bridge has 2+ remote
   links). STP-converged triangle passes cross-host pings in ~0.4-1.2ms.
6. **isolation** — port isolation / VLAN pairs.
7. **dpctl + DPDK** — ovs-dpctl surface (add-dp/add-if/show/dump-flows)
   only where userspace datapaths matter; DPDK rebuild of openvswitch as
   a separate package variant. A platform that keeps institutions, home
   users and businesses off SaaS control planes entirely.

## Non-goals

- No daemon, no database server beyond OVS's own ovsdb.
- No dashboard in the loop; the commands are the interface.
- No global "apply everything" — each command is one task, done well.
