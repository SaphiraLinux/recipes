# wendzelnntpd (Saphira native package)

WendzelNNTPd v2.2.0-alpha ("Bad Woerishofen", upstream tag `v2.2.0-alpha`,
https://github.com/cdpxe/WendzelNNTPd) packaged for Saphira Linux.

- Backend: SQLite (upstream default; MySQL/Postgres support exists upstream
  but is not this package's target).
- Protocols: NNTP (default port 119) and TLS/NNTPS (native connectors,
  STARTTLS; typical deployment listens on 119 and 563). IPv4/IPv6 listen
  addresses and ports are configured with upstream "connectors".
- Configuration: `/etc/wendzelnntpd/wendzelnntpd.conf` (apk protected-config;
  survives upgrades via the usual `.apk-new` mechanism).
- TLS certificates: `/etc/wendzelnntpd/ssl/` - operator-owned. The package
  never generates certificates at install; run
  `/usr/sbin/wendzelnntpd-setup` to pick the FQDN and optionally obtain a
  Let's Encrypt certificate via certbot (standalone, TCP/80). Renewals are
  automatic: the certbot package ships `/etc/cron.daily/certbot-renew`
  (daily, renews inside certbot's 30-day pre-expiry window) and this
  package ships the deploy hook
  `/etc/letsencrypt/renewal-hooks/deploy/wendzelnntpd`, which copies the
  renewed certificate into `/etc/wendzelnntpd/ssl/` and restarts the
  service if it is running. Operators may instead place their own
  `server.key`/certificate there or use upstream's
  `/usr/sbin/create_certificate`.
- Database and postings: `/var/spool/news/wendzelnntpd/` (SQLite `usenet.db`
  created idempotently on first service start from the packaged schema at
  `/usr/share/wendzelnntpd/usenet.db_struct`; an existing database is never
  touched by upgrades).
- Account: system user `news` (UID/GID 12) from the saphira-baselayout
  account registry owns the spool semantics; the daemon itself runs as root
  per upstream (binding TCP/119) - upstream has no privilege drop.
- Services: OpenRC `/etc/init.d/wendzelnntpd`, systemd
  `/usr/lib/systemd/system/wendzelnntpd.service`. Nothing is auto-enabled:
  start with `rc-service wendzelnntpd start` or `systemctl start
  wendzelnntpd` after configuring.

Basic first start:

1. Run `wendzelnntpd-setup` (asks for the FQDN; optional certbot issuance
   places `server.crt`/`server.key` under `/etc/wendzelnntpd/ssl/` with
   automatic renewal).
2. Edit `/etc/wendzelnntpd/wendzelnntpd.conf` (database-engine stays
   `sqlite3`; define connectors for NNTP and NNTPS; TLS certificates live
   under `/etc/wendzelnntpd/ssl/`).
3. Create admin users and newsgroups with `wendzelnntpadm`
   (`adduser`, `addgroup`, ...; see `man wendzelnntpadm`).
4. Start the service (OpenRC or systemd; not enabled by default).

Initial role is small/local/public discussion (no INN-style peering;
upstream does not implement server-to-server feeds).
