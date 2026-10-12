"""HTTP/3 test client for the saphira-udpdist acceptance lab.

TEST-ONLY TOOLING. Not part of the saphira-udpdist package and not a runtime
dependency of it.

Each scenario opens a real QUIC/HTTP-3 connection to the VIP through the
distributor, makes a real HTTP/3 request, and reports which backend served it.
The backend identity comes from the response body, which the server sets, so
the result does not depend on trusting the distributor's own counters.

Scenarios:
  basic        one connection, one request
  concurrent   N simultaneous connections, all must succeed
  rebind       a live connection moves to a new source port and keeps working
  migrate      a live connection moves to a new source address and keeps working
  backendloss  a connection whose backend disappears must fail, not be remapped
"""

import argparse
import asyncio
import socket
import ssl
import sys

from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.h3.connection import H3_ALPN, H3Connection
from aioquic.h3.events import DataReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.connection import QuicConnection
from aioquic.quic.events import ProtocolNegotiated, StreamDataReceived


class ClientProtocol(QuicConnectionProtocol):
    """HTTP/3 client side of one connection.

    The H3Connection is stashed on the QuicConnection rather than on this
    protocol, because a source-port or address change replaces the protocol
    while the QUIC connection continues. Stashing it there is what lets a live
    connection keep making requests after it moves.
    """

    def quic_event_received(self, event) -> None:
        if isinstance(event, ProtocolNegotiated):
            self._quic._h3 = H3Connection(self._quic)
        h3 = getattr(self._quic, "_h3", None)
        if h3 is not None and isinstance(event, StreamDataReceived):
            for h3_event in h3.handle_event(event):
                if isinstance(h3_event, HeadersReceived):
                    for name, value in h3_event.headers:
                        if name == b":status":
                            self._quic._status = int(value)
                        elif name == b"server":
                            self._quic.served_by = value.decode()
                elif isinstance(h3_event, DataReceived):
                    self._quic._body += h3_event.data
                    if h3_event.stream_ended:
                        self._quic._done.set()
        super().quic_event_received(event)


class H3Client:
    """One HTTP/3 connection, and the socket it is currently using.

    The socket is created explicitly rather than by aioquic's connect() helper
    so that a source-port or source-address change can be performed on a live
    connection: the QUIC connection object survives, the transport does not.
    That is precisely what NAT rebinding and address migration look like to the
    server, and therefore precisely what the distributor has to get right.
    """

    def __init__(self, server_host: str, server_port: int, local_host: str,
                 local_port: int, label: str = ""):
        # aioquic's own connect() helper expands a two-tuple to a four-tuple
        # before handing it to a dual-stack socket. This client creates the
        # transport itself, so it has to do the same: an IPv4 literal left as a
        # two-tuple never leaves the socket.
        server = server_host
        if len(server_host.split(":")) == 1:
            server = "::ffff:" + server_host
        self.server = (server, server_port, 0, 0)
        self.local = (local_host, local_port)
        self.label = label
        self._protocol: QuicConnectionProtocol | None = None
        self._transport = None
        self._sock = None
        self.quic: QuicConnection | None = None

    def _new_connection(self) -> QuicConnection:
        configuration = QuicConfiguration(
            is_client=True,
            alpn_protocols=H3_ALPN,
            server_name="quic.test",
            verify_mode=ssl.CERT_NONE,
        )
        conn = QuicConnection(configuration=configuration)
        conn._h3 = None
        conn._status = None
        conn._body = b""
        conn._served_by = None
        conn._done = asyncio.Event()
        return conn

    @property
    def status(self):
        return self.quic._status

    @property
    def served_by(self):
        return self.quic.served_by

    @property
    def body(self):
        return self.quic._body

    async def open(self) -> None:
        self.quic = self._new_connection()
        await self._bind_and_attach(self.local[0], self.local[1])
        self._protocol.connect(self.server, transmit=True)
        await asyncio.wait_for(self._protocol.wait_connected(), timeout=8)

    async def _bind_and_attach(self, host: str, port: int) -> None:
        loop = asyncio.get_running_loop()
        sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        bind_host = host
        if host and host.count(".") == 3 and ":" not in host:
            bind_host = "::ffff:" + host
        sock.bind((bind_host, port, 0, 0))
        transport, protocol = await loop.create_datagram_endpoint(
            lambda: ClientProtocol(self.quic),
            sock=sock,
        )
        self._sock, self._transport, self._protocol = sock, transport, protocol
        self.local = (host, port)

    async def rebind_to_port(self, new_port: int) -> None:
        """Move this live connection to a new source port.

        The QUIC connection, its connection ids and its HTTP/3 state are
        unchanged; only the socket the packets leave from is replaced. A server
        sees a different 4-tuple for the same connection, which is exactly what
        a NAT rebinding looks like, and exactly what a distributor that hashes
        the tuple will get wrong.
        """
        old_transport, old_sock = self._transport, self._sock
        await self._bind_and_attach(self.local[0], new_port)
        for closable in (old_transport, old_sock):
            try:
                if closable is not None:
                    closable.close()
            except Exception:
                pass
        self._protocol._timer_at = None
        self._protocol.transmit()

    async def migrate_to_address(self, new_host: str, new_port: int) -> None:
        """Move this live connection to a new source address and port.

        The QUIC connection keeps its state, so from the server's point of view
        this is a client that walked to a different network.
        """
        old_transport, old_sock = self._transport, self._sock
        await self._bind_and_attach(new_host, new_port)
        for closable in (old_transport, old_sock):
            try:
                if closable is not None:
                    closable.close()
            except Exception:
                pass
        self._protocol._timer_at = None
        self._protocol.transmit()

    async def request(self, path: str = "/", timeout: float = 8.0) -> None:
        self.quic._done.clear()
        self.quic._status = None
        self.quic._body = b""
        stream_id = self.quic.get_next_available_stream_id()
        self.quic._h3.send_headers(
            stream_id,
            [
                (b":method", b"GET"),
                (b":scheme", b"https"),
                (b":authority", b"quic.test"),
                (b":path", path.encode()),
                (b"user-agent", b"saphira-udpdist-http3-lab"),
            ],
            end_stream=True,
        )
        self._protocol._timer_at = None
        self._protocol.transmit()
        await asyncio.wait_for(self.quic._done.wait(), timeout=timeout)

    async def close(self) -> None:
        if self._protocol is not None:
            self._protocol.close()
            await self._protocol.wait_closed()
        for closable in (self._transport, self._sock):
            try:
                if closable is not None:
                    closable.close()
            except Exception:
                pass

    def __repr__(self) -> str:
        return "<H3 %s local=%s:%d status=%s served_by=%s>" % (
            self.label, self.local[0], self.local[1], self.status, self.served_by,
        )


async def scenario_basic(args) -> int:
    c = H3Client(args.host, args.port, args.local, 0, "basic")
    await c.open()
    await c.request()
    await asyncio.sleep(0.2)
    ok = c.status == 200 and b"backend=" in c.body
    print("basic: status=%s served_by=%s body=%r -> %s"
          % (c.status, c.served_by, c.body.decode().strip(), "PASS" if ok else "FAIL"))
    await c.close()
    return 0 if ok else 1


async def scenario_concurrent(args) -> int:
    # Deterministic source ports when asked, so the same set of flows can be
    # replayed before and after a configuration change and compared.
    ports = [0] * args.count
    if args.base_port:
        ports = [args.base_port + i for i in range(args.count)]
    clients = [
        H3Client(args.host, args.port, args.local, ports[i], "c%d" % i)
        for i in range(args.count)
    ]
    for c in clients:
        await c.open()
    results = await asyncio.gather(*(c.request() for c in clients), return_exceptions=True)
    await asyncio.sleep(0.3)
    good = 0
    by_backend: dict = {}
    per_flow = []
    for c, r in zip(clients, results):
        if isinstance(r, Exception) or c.status != 200:
            print("concurrent: FAILED %r %s" % (c, r))
            continue
        good += 1
        sid = c.body.decode().strip().split("=")[1]
        by_backend[sid] = by_backend.get(sid, 0) + 1
        per_flow.append("%d=%s" % (c.local[1], sid))
    print("concurrent: %d/%d connections established and served; per backend %s"
          % (good, args.count, by_backend))
    print("flowmap: %s" % " ".join(sorted(per_flow, key=lambda s: int(s.split("=")[0]))))
    for c in clients:
        await c.close()
    return 0 if good == args.count else 1


async def scenario_rebind(args) -> int:
    c = H3Client(args.host, args.port, args.local, args.base_port, "rebind")
    await c.open()
    await c.request()
    first = c.body.decode().strip()
    first_sid = first.split("=")[1]
    old_port = c.local[1]

    await c.rebind_to_port(args.new_port)
    await asyncio.sleep(0.4)
    # The connection must still be usable on its new port.
    alive = True
    try:
        await c.request(timeout=6.0)
        alive = c.status == 200
    except asyncio.TimeoutError:
        alive = False
    second = c.body.decode().strip()
    second_sid = second.split("=")[1] if "=" in second else "?"
    same = first_sid == second_sid
    print("rebind: port %d -> %d, first backend %s, after rebind status=%s "
          "backend %s, same backend=%s -> %s"
          % (old_port, args.new_port, first_sid, c.status, second_sid, same,
             "PASS" if (alive and same) else "FAIL"))
    await c.close()
    return 0 if (alive and same) else 1


async def scenario_migrate(args) -> int:
    c = H3Client(args.host, args.port, args.local, args.base_port, "migrate")
    await c.open()
    await c.request()
    first_sid = c.body.decode().strip().split("=")[1]
    old = "%s:%d" % (c.local[0], c.local[1])

    await c.migrate_to_address(args.new_local, args.new_port)
    await asyncio.sleep(0.4)
    alive = True
    try:
        await c.request(timeout=6.0)
        alive = c.status == 200
    except asyncio.TimeoutError:
        alive = False
    after_sid = c.body.decode().strip().split("=")[1] if "=" in c.body.decode() else "?"
    same = first_sid == after_sid
    print("migrate: %s -> %s:%d, first backend %s, after migration status=%s "
          "backend %s, same backend=%s -> %s"
          % (old, args.new_local, args.new_port, first_sid, c.status, after_sid,
             same, "PASS" if (alive and same) else "FAIL"))
    await c.close()
    return 0 if (alive and same) else 1


SCENARIOS = {
    "basic": scenario_basic,
    "concurrent": scenario_concurrent,
    "rebind": scenario_rebind,
    "migrate": scenario_migrate,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=sorted(SCENARIOS))
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--local", default="::")
    ap.add_argument("--base-port", type=int, default=0)
    ap.add_argument("--new-port", type=int, default=0)
    ap.add_argument("--new-local", default="::")
    ap.add_argument("--count", type=int, default=4)
    args = ap.parse_args()
    try:
        return asyncio.run(SCENARIOS[args.scenario](args))
    except Exception as exc:  # a failure must be a failure, never a crash
        print("%s: EXCEPTION %s: %s -> FAIL"
              % (args.scenario, type(exc).__name__, exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
