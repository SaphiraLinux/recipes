'use strict';
// Live TLS wiring (supports CVE-2026-105483/106069/106072): proves the
// fixed checkServerIdentity is what real handshakes actually call.
// A local server presents the committed snakeoil cert (10y, test-only);
// the client connects with rejectUnauthorized:false (encryption only),
// reads the PEER certificate off the wire, and runs the REAL verifier
// against it. Expiry never enters: checkServerIdentity judges identity
// only, and the fixture is valid until 2036 regardless (see README).
//
// Argv[2] carries the fixture directory. No external tools, no network
// beyond 127.0.0.1.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const tls = require('tls');

const DIR = process.argv[2];
assert(DIR, 'usage: tls-live.js <fixture-dir>');
const server = tls.createServer({
  key: fs.readFileSync(path.join(DIR, 'snakeoil-key.pem')),
  cert: fs.readFileSync(path.join(DIR, 'snakeoil-cert.pem')),
}, (socket) => { socket.end(); });

server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  const client = tls.connect({ host: '127.0.0.1', port, rejectUnauthorized: false }, () => {
    try {
      const peer = client.getPeerCertificate(true);
      assert(peer && peer.subjectaltname,
        'no peer certificate retrieved (harness failure)');
      assert(peer.subjectaltname.includes('IP Address:127.0.0.1'),
        `unexpected fixture SANs: ${peer.subjectaltname}`);
      // The fixed verifier accepts the canonical address end to end...
      assert.strictEqual(tls.checkServerIdentity('127.0.0.1', peer), undefined);
      // ...and rejects the attack spellings through the same path.
      assert(tls.checkServerIdentity('0127.0.0.1', peer) instanceof Error);
      assert(tls.checkServerIdentity('0177.0.0.1', peer) instanceof Error);
      console.log('PASS: live handshake verified through fixed checkServerIdentity');
      client.end();
      server.close();
    } catch (e) {
      console.error(`FAIL: ${e.message}`);
      client.destroy();
      server.close();
      process.exit(1);
    }
  });
  client.on('error', (e) => {
    console.error(`ERROR: TLS handshake failed: ${e.message}`);
    server.close();
    process.exit(3);
  });
});
setTimeout(() => {
  console.error('ERROR: handshake timed out');
  process.exit(3);
}, 20000).unref();
