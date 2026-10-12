# saphira-bridge status

Recorded so that the next session does not rediscover this from scratch.

## Proven

- `tests/regress.sh`: 22 passed, 0 failed.
  - clean build of every translation unit under
    `-Wall -Wextra -Wpedantic -Werror`
  - no process execution in `src/`
  - links against libc only
  - 11 configuration refusals proven through the binary
- `tests/unit.c`: 120 checks, 0 failures. CAM insert/lookup/move/age/evict and
  the expiry-before-eviction rule; the forwarding decision table; reserved and
  tagged drops; multicast-source refusal; self-addressed drop.

## RESOLVED: the frame explosion was self-capture, and the auxdata flag was lying

The millions-per-second frames were the bridge receiving **its own
transmissions**. A promiscuous packet socket sees outgoing frames, so a frame
written to one port was read back on that port, judged to need forwarding, and
written out the others.

The important part is *how it was recognised*, because the first fix did not work:

    with PACKET_IGNORE_OUTGOING off, so the kernel delivers our own frames:

        g: rx=4 forwarded=4 (unicast=3 flooded=1)
         drops: total=0 ... self_echo=5
         direction: self_echo=5 (sll_pkttype) auxdata_outgoing=0 ignore_outgoing=0
         pkttype: host=0 broadcast=1 multicast=0 otherhost=3 outgoing=5 unknown=0

    self_echo      = 5   frames rejected, on sll_pkttype
    pkttype:outgoing = 5 the same frames, identified as ours
    auxdata_outgoing = 0  the auxdata status bit reported NONE of them

`TP_STATUS_OUTGOING` was reporting zero while `sll_pkttype` reported five. The
auxdata is not populated for a frame transmitted on a *different* descriptor
(`tx_fd`) from the one bound for receive, so the earlier "fix" was silently
inert and the storm survived it. Direction is now decided by `sll_pkttype`, with
`PACKET_IGNORE_OUTGOING` as the preferred kernel-side suppression underneath and
the `sll_pkttype` check kept as the authoritative policy underneath that. The
counters are separate, so either mechanism can be shown to be the one doing the
work.

    with both enabled, the default:

        f: rx=4 forwarded=4 (unicast=3 flooded=1)
         drops: total=0 ... self_echo=0
         direction: self_echo=0 (sll_pkttype) auxdata_outgoing=0 ignore_outgoing=1
         pkttype: host=0 broadcast=1 multicast=0 otherhost=3 outgoing=0 unknown=0

    rx=0 when idle, rx=4 for one ping, and the ping succeeds in both directions.

`ignore_outgoing=0` makes the lab fall back to the `sll_pkttype` check alone, so
the two can be compared; `sample=N` logs every Nth frame with its addresses,
packet type, length and ethertype, which is how the VLAN finding below was made.

## ACCEPTANCE MET, from clean committed trees

All three suites re-run from fresh clones of what is committed, with nothing
built beforehand and no staged copy involved:

    saphira-bridge   regress.sh      22 passed, 0 failed   124 policy checks
    saphira-bridge   bridge-lab.sh   21 passed, 0 failed
    saphira-udpdist  tests/lab.sh    15 passed, 0 failed

The udpdist run is the one that matters, and it is now committed rather than
staged. `saphira-udpdist/tests/lab.sh` joins the segment with this daemon instead
of `ip -n lan link add br0 type bridge`, committed on its own so the provenance
is obvious. Not one line of any of the fifteen DSR assertions changed, and the
count is still fifteen.

The offload state that run actually executed under, read from the veths:

    cli0  tx-checksum-ip-generic: off     udpdist's own prerequisite
    lb0   tx-checksum-ip-generic: off     udpdist's own prerequisite
    b10   tx-checksum-ip-generic: on      the stress case
    b20   tx-checksum-ip-generic: on      the stress case

The backends offload and the client and distributor do not, and that is
deliberate in both directions. udpdist verifies a transport checksum rather than
guessing, so it will not accept a frame whose sender has not written the checksum
yet - that is why the legs it redirects on must have offload off, and it is its own
documented prerequisite. The backends are the third party and the case this
segment exists to survive, so they are left offloading. Setup now refuses to
produce an acceptance result if they are not, because a test that cannot tell the
strong pass from the weak one is not an acceptance test.

Earlier results in this file came from a staged copy of the lab with an offload
switch, and are developmental evidence only. The committed lab is the final
evidence.

### A pre-existing bug this uncovered

The lab's offload loop spelled the interfaces `"${n}0"`, which is `be10` and
`be20`, not `b10` and `b20`, so it silently missed both backends and left them
offloading by accident. It was never doing what its comment said. It did not
matter for udpdist, which only needs the leg it redirects on, and the accidental
outcome happened to be the one wanted - which is exactly the kind of luck that
should be replaced by a decision, so the loop is now explicit about which legs
are cleaned and why the others are not.

### A second pre-existing fragility

`bridge-lab.sh` depended on the daemon and its probe being built, and both are
deliberately not committed. A clean checkout had neither, and the lab failed in a
way that had nothing to do with what it measures. It now builds what it needs, so
the 21/21 above comes from a brand-new clone with nothing in it.

## Defects found and fixed along the way

- **`forwarded` counted port writes, not frames**, so `unicast + flooded =
  forwarded` could not hold. A counter set that does not add up is worse than no
  counter set. `forwarded` now counts frames; per-port counters count writes.
- **Transmit reused the receive descriptor.** udpdist uses a separate `tx_fd`, and
  a bridge whose writes silently vanish is the worst failure this daemon could
  have. Now a separate descriptor per port, matching the proven arrangement.
- **A promiscuous socket sees the bridge's own transmissions.** Unhandled, a frame
  sent out one port is read back on that port, judged to need forwarding, and sent
  out the others. Fixed with `TP_STATUS_OUTGOING` and counted as `self_echo`.
- **A refused learning was modelled as a drop reason**, so a forwarded frame
  cleared the counter that exists to notice the refusal. `not_learned` is now a
  separate observation.
- **Port names longer than `IFNAMSIZ` were accepted** and could not be
  represented in the kernel interface structure. Caught by the compiler.

## Test-instrument bugs, recorded because they were mistaken for daemon bugs

Worth the same respect as the daemon defects, and they cost most of the session:

- `br-probe recv` exited after seeing `want` frames of *any* kind, so a single
  unrelated MLD frame closed the window before the frame under test arrived. It
  now waits for frames addressed to it.
- The receiver was not promiscuous, so the kernel correctly withheld frames not
  addressed to it, and a working forwarding rule was reported as broken.
- A promiscuous receiver also sees background traffic, so `total=0` is not a
  meaningful assertion; counting is restricted to this tool's own payload marker.
- A bare `wait` in the lab waits for *every* background job, including the bridge
  daemon, which never exits.
- The lab reused a stale log from a previous run, so assertions read someone
  else's numbers.
- Accounting sampled three separate counter dumps on a live segment, comparing
  counters taken at different moments. It now takes one snapshot.
- One diagnostic compared a receiver waiting for one MAC against a sender hardcoded
  to another; the conclusion drawn from it was wrong, and re-measuring was the only
  way out.
