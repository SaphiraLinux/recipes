"""HTTP/3 test server for the saphira-udpdist acceptance lab.

TEST-ONLY TOOLING. Not part of the saphira-udpdist package and not a runtime
dependency of it.

aioquic does not implement QUIC-LB, so this server emits plaintext routable
connection ids: the three-bit configuration codepoint, then the server id, then
a random nonce. udpdist is configured with the matching quic_config. This is the
unkeyed routing scheme, which the load-balancer specification allows; the
encrypted scheme is deferred in udpdist and is not exercised here.

Each backend runs its own process with its own --sid, which is the same model a
real pool uses: identical parameters across the pool, distinct server ids.
"""

import argparse
import asyncio
import datetime
import os
import sys
import tempfile

import aioquic.asyncio.server as aioquic_server
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.h3.connection import H3_ALPN, H3Connection
from aioquic.h3.events import DataReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.connection import QuicConnection
from aioquic.quic.events import ProtocolNegotiated, StreamDataReceived

CONFIG_ID = 2
CID_LEN = 8
SERVER_ID_LEN = 2


def routable_cid(server_id: int) -> bytes:
    """A plaintext QUIC-LB connection id: config codepoint, server id, nonce.

    The configuration codepoint occupies the first three bits of the first octet,
    which is where udpdist reads the connection-id length from, and the server
    id follows immediately so the load balancer can route without any table.
    """
    nonce = os.urandom(CID_LEN - 1 - SERVER_ID_LEN)
    return bytes([CONFIG_ID << 5]) + server_id.to_bytes(SERVER_ID_LEN, "big") + nonce


class QuicLbConnection(QuicConnection):
    """A server connection whose every issued connection id is routable.

    The first connection id is the one the client learns from the server's long
    header Source Connection ID and then uses as its Destination Connection ID,
    so it must be routable. Later ids arrive via NEW_CONNECTION_ID and are
    equally routable, which is what lets a connection survive a rebinding: the
    client switches to a different address but keeps addressing the same server
    by a routable id.
    """

    def __init__(self, *args, server_id: int = 0, **kwargs):
        self._lb_server_id = server_id
        self._lb_rewritten: set = set()
        super().__init__(*args, **kwargs)
        if not self._is_client:
            self._lb_rewrite(self._host_cids)

    def _lb_rewrite(self, cids) -> None:
        for c in cids:
            if bytes(c.cid) in self._lb_rewritten:
                continue
            c.cid = routable_cid(self._lb_server_id)
            self._lb_rewritten.add(bytes(c.cid))
        if self._host_cids:
            self.host_cid = self._host_cids[0].cid
            self._local_initial_source_connection_id = self._host_cids[0].cid

    def _replenish_connection_ids(self) -> None:
        before = len(self._host_cids)
        super()._replenish_connection_ids()
        if not self._is_client:
            self._lb_rewrite(self._host_cids[before:])


class H3Protocol(QuicConnectionProtocol):
    """Serves one minimal HTTP/3 resource per request stream.

    The response names the backend that answered, so the client can report which
    backend actually served it without trusting the distributor's counters.
    """

    server_id = 0
    log_path = ""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # One answer per request stream. A request whose headers and body arrive
        # in separate datagrams re-delivers HeadersReceived, and answering twice
        # writes after the stream is already finished.
        self._answered: set = set()

    def quic_event_received(self, event) -> None:
        if isinstance(event, ProtocolNegotiated):
            self._http = H3Connection(self._quic)
        http = getattr(self, "_http", None)
        if http is not None and isinstance(event, StreamDataReceived):
            for h3_event in http.handle_event(event):
                if isinstance(h3_event, HeadersReceived):
                    # Only a client-initiated bidirectional request stream is
                    # answerable. QPACK and control data also arrive as
                    # unidirectional streams, and answering one of those raises.
                    if (any(n == b":method" for n, _ in h3_event.headers)
                            and h3_event.stream_id not in self._answered):
                        self._answered.add(h3_event.stream_id)
                        self._answer(h3_event)
                elif isinstance(h3_event, DataReceived) and h3_event.stream_ended:
                    pass
        super().quic_event_received(event)

    def _answer(self, event: HeadersReceived) -> None:
        path = "/"
        for name, value in event.headers:
            if name == b":path":
                path = value.decode(errors="replace")
        body = ("backend=%d\n" % self.server_id).encode()
        # Through the HTTP/3 object, not the raw connection: the raw API writes
        # bytes with no HTTP/3 framing, which the client cannot parse.
        self._http.send_headers(
            event.stream_id,
            [(b":status", b"200"),
             (b"server", b"saphira-http3-lab/%d" % self.server_id)],
        )
        self._http.send_data(event.stream_id, body, end_stream=True)
        self.transmit()
        if self.log_path:
            peer = "%s:%d" % self._remote_address[:2]
            with open(self.log_path, "a") as fh:
                fh.write("served path=%s peer=%s\n" % (path, peer))


def make_cert(directory: str) -> tuple[str, str]:
    """A throwaway self-signed certificate for the test hostname.

    Generated at run time and never committed: the lab proves distributor
    behaviour, and a fixed private key in a repository would be a credential in
    source control. The client does not verify it, which is acceptable here
    precisely because it is a loopback lab with a per-run key.
    """
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "quic.test")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName("quic.test")]), critical=False
        )
        .sign(key, hashes.SHA256())
    )
    cert_path = os.path.join(directory, "cert.pem")
    key_path = os.path.join(directory, "key.pem")
    with open(cert_path, "wb") as fh:
        fh.write(cert.public_bytes(serialization.Encoding.PEM))
    with open(key_path, "wb") as fh:
        fh.write(
            key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        )
    os.chmod(key_path, 0o600)
    return cert_path, key_path


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", required=True, help="address to bind (the VIP)")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--sid", type=int, required=True, help="QUIC-LB server id")
    ap.add_argument("--log", default="")
    ap.add_argument("--certdir", default="")
    args = ap.parse_args()

    certdir = args.certdir or tempfile.mkdtemp(prefix="ud-http3-cert.")
    cert, key = make_cert(certdir)

    configuration = QuicConfiguration(is_client=False, alpn_protocols=H3_ALPN)
    configuration.load_cert_chain(cert, key)
    configuration.connection_id_length = CID_LEN

    def connection_factory(**kwargs):
        return QuicLbConnection(server_id=args.sid, **kwargs)

    aioquic_server.QuicConnection = connection_factory

    class Protocol(H3Protocol):
        server_id = args.sid
        log_path = args.log

    await serve_with(args, configuration, Protocol)
    print(
        "http3 server ready bind=%s:%d sid=%d cid_len=%d config_id=%d"
        % (args.bind, args.port, args.sid, CID_LEN, CONFIG_ID),
        flush=True,
    )
    await asyncio.Future()
    return 0


async def serve_with(args, configuration, protocol) -> None:
    await aioquic_server.serve(
        args.bind,
        args.port,
        configuration=configuration,
        create_protocol=protocol,
        stream_handler=None,
    )


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
