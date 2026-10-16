# Installation on Debian 13 — SendmailAnalyzer 10

Use the latest published Debian revision of the `sendmailanalyzer` package. The canonical package name is
`sendmailanalyzer`; the temporary development package name `sendmailanalyzer10`
is supported only for upgrade cleanup compatibility.

## Recommended installation

Use APT so missing dependencies are resolved automatically:

```sh
apt install ./sendmailanalyzer_VERSION_all.deb
```

`dpkg -i` does not download missing dependencies and should only be used when
they are already present.

## Production paths

- configuration: `/etc/sendmailanalyzer.conf`
- data/SQLite: `/var/lib/sendmailanalyzer/`
- application: `/usr/lib/sendmailanalyzer/`
- documentation: `/usr/share/doc/sendmailanalyzer/`
- backups: `/var/backups/sendmailanalyzer/`
- services: `sendmailanalyzer-collector.service` and `sendmailanalyzer-web.service`
- service account: `sendmailanalyzer`

Final installations do not use `sendmailanalyzer10` runtime paths.

## What the package does automatically

1. Backs up the active v10 configuration and collector state before unpacking.
2. If a production v10 SQLite database exists, checkpoints and validates it and
   creates a consistent rollback copy.
3. Preserves all existing configuration values and adds only missing mandatory
   parameters introduced by the new revision.
4. Creates/updates the `sendmailanalyzer` service account and least-privilege
   read access for current and rotated `mail.log*` and `rspamd.log*` files.
5. Applies compatible/additive SQLite schema migrations through the v10 storage
   layer without automatically re-importing legacy 9.4 history.
6. Runs `sa10_selftest` and SQLite `PRAGMA quick_check`.
7. On a running systemd host, enables and starts/restarts only the
   SendmailAnalyzer collector and web services.
8. If Apache is available, offers a dedicated HTTPS reporting host such as
   `reports.example.test` instead of creating a fresh `/reports/` path proxy.
9. Reuses an existing unexpired TLS certificate that covers the reporting
   FQDN, creates bcrypt Basic Auth credentials for WAN clients, and permits
   localhost plus one configured LAN CIDR without authentication.
10. If the selected base domain is an authoritative local static BIND zone,
    adds the A record transactionally. A manually signed DNSSEC zone is
    re-signed with its existing keys and validated before activation.
11. Runs `apache2ctl configtest` and reloads Apache only when required.
12. On validation failure, attempts to restore the previous v10 SQLite
    snapshot, reporting-site files and prior SendmailAnalyzer service state.

Current package revisions **do not automatically import or retire
SendmailAnalyzer 9.4**. Legacy migration tools are explicit/manual only.

The package does not restart Postfix, Rspamd, Dovecot, rsyslog, SSH, firewall or
network services.

## Configuration

`/etc/sendmailanalyzer.conf` documents every parameter in English. The complete
reference is `CONFIGURATION.md`.

After changing configuration:

```sh
/usr/bin/sa10_selftest --config /etc/sendmailanalyzer.conf
```

## Validation

```sh
systemctl is-enabled sendmailanalyzer-collector.service sendmailanalyzer-web.service
systemctl is-active sendmailanalyzer-collector.service sendmailanalyzer-web.service
/usr/bin/sa10_selftest --config /etc/sendmailanalyzer.conf
runuser -u sendmailanalyzer -- /usr/bin/sa10_db \
  --config /etc/sendmailanalyzer.conf --cmd quick-check
```

On a production system the expected results are `enabled`, `active`,
`RESULT: PASS`, and SQLite `ok`.

## Dedicated HTTPS reporting site

The preferred production layout is a dedicated host such as
`reports.example.test`, reverse-proxied at `/` to `127.0.0.1:9080`.

During an interactive Debian installation the package asks for the existing
base domain, reporting label, IPv4 address, Basic Auth username/password and
optional LAN CIDR. An existing dedicated root-proxy installation is detected
and preserved, including its certificate and existing authentication hash.

Localhost and the configured LAN can access the reporting site directly.
Other clients must authenticate through Apache Basic Auth. The clear-text
password is supplied to `htpasswd -B -i` through standard input and cleared
from Debconf after use; only the bcrypt htpasswd hash remains on disk.

The installer reuses an already-present unexpired certificate only when
OpenSSL verifies that it covers the requested FQDN. It does not expose Basic
Auth credentials over an automatically generated plain-HTTP reporting site.

When the base domain is an authoritative local static BIND zone, the installer
can create the A record. For manually signed static DNSSEC zones it builds a
candidate zone, increments the SOA serial, validates it with `named-checkzone`,
re-signs it with the existing keys using `dnssec-signzone`, validates the
result with `dnssec-verify`, and only then replaces the live zone and reloads
BIND. SendmailAnalyzer never creates or rotates DNSSEC keys and installs no
DNSSEC maintenance cron job.

If DNS is hosted externally, the package leaves it unchanged and reports the
A record that the administrator must create. It never requests or stores DNS
provider credentials.

In a non-interactive installation where no existing Basic Auth user exists and
no password has been preseeded, the core package is installed but the new WAN
site is not created. This prevents accidental unauthenticated exposure.

Legacy `/reports/` integrations remain understood by the migration helper for
compatibility, but they are no longer the preferred fresh-install layout.

The manual Apache example is installed as:

```text
/usr/share/doc/sendmailanalyzer/apache2-sendmailanalyzer.conf
```

## Building from source

The source archive contains a complete `debian/` directory:

```sh
dpkg-buildpackage -us -uc -b
```

The resulting package is:

```text
sendmailanalyzer_VERSION_all.deb
```

See `DEPENDENCIES.md`, `CONFIGURATION.md` and `MIGRATION-9.4.md` for details.
