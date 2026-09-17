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
8. If Apache is installed and SendmailAnalyzer integration already exists,
   migrates/normalizes that integration, preserves custom route/`Require` rules,
   runs `apache2ctl configtest`, and performs only an Apache reload when the
   configuration changed.
9. On validation failure, attempts to restore the previous v10 SQLite snapshot
   and prior SendmailAnalyzer service state.

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

## Apache

`/reports/` is the recommended route. Package migration logic preserves an
existing custom route when appropriate and preserves `Require` access rules per
HTTP/HTTPS VirtualHost. Deprecated `/sareport/` or temporary `/sareport10/`
routes are not recreated when `/reports/` is already the active route.

A secure example configuration using `Require local` is installed as:

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
