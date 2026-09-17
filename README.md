# SendmailAnalyzer 10.0.16

SendmailAnalyzer 10 is a Postfix-first modernization of the original
SendmailAnalyzer reporting concept. It correlates real mail-flow logs into a
persistent SQLite database and provides a read-only web dashboard, JSON API and
Prometheus-style metrics.

The project deliberately separates three concepts that are not equivalent on a
modern mail system:

1. **filter verdicts** from SpamAssassin, Rspamd, ClamAV, DKIM and DMARC;
2. **transport state** such as sent, bounced and deferred;
3. **final disposition** such as delivered, rejected or blocked.

A SpamAssassin spam verdict therefore does not automatically mean that the MTA
rejected the message.

## Current revision

`10.0.16-16` is the publication-hygiene revision built on the validated
`10.0.16-15` production baseline. It keeps the same parser, collector, SQLite,
Apache and site-local configuration behavior while replacing the remaining
production-derived fixture identifiers, neutralizing internal test naming,
strengthening publication checks and making package-installation documentation
revision-independent.

Since `10.0.16-9`, an existing v10 SQLite database is **authoritative**. Normal
package upgrades preserve and validate it in place. A fresh installation starts
with an empty v10 SQLite database and collects the configured real logs.
SendmailAnalyzer 9.4 migration helpers remain available for explicit/manual use
but are not executed automatically by package installation.

The package creates rollback material before an upgrade, preserves local
configuration and collector state, validates SQLite and the application, and on
a running Debian/systemd host enables/restarts only its own collector and web
services. It does not restart Postfix, Rspamd, Dovecot, rsyslog, SSH, firewall
or network services. Existing Apache integration is validated and reloaded only
when its SendmailAnalyzer configuration actually changes.

## Web interface

The web interface keeps the useful report organization associated with classic
SendmailAnalyzer while using a modern responsive implementation:

- compact year/month selector;
- compact day calendar;
- 24-hour selector for daily views;
- monthly, daily and hourly reports;
- sidebar areas for messaging, spam, virus, DSN, rejections, authentication,
  TLS, Rspamd and top statistics;
- disabled calendar/navigation controls for periods with no stored data;
- read-only detail pages, JSON API and metrics;
- no external JavaScript dependency.

Branding is intentionally text-only. The historical Sendmail "Bat" logo is not
shipped by SendmailAnalyzer 10.

## Architecture

```text
mail.log -----------------+
rspamd.log ---------------+
rotated .log/.gz ----------+  replay only for historical files
                           |
                           v
                    modular parsers
       +-------------------+-------------------+
       | Postfix / LMTP / SMTP                |
       | Postscreen / DNSBL                   |
       | SpamAssassin                         |
       | Rspamd                               |
       | OpenDKIM / OpenDMARC                 |
       | ClamAV                               |
       | Dovecot                              |
       +-------------------+-------------------+
                           |
                           v
                    structured events
                           |
                           v
              Queue-ID / Message-ID correlation
                           |
                           v
                     classifier
       +-------------------+-------------------+
       | direction: inbound/outbound/internal/relay
       | transport: sent/bounced/deferred
       | spam detected / rejected / delivered
       +-------------------+-------------------+
                           |
                           v
                         SQLite
                      /          \
                 JSON API     read-only PSGI web
```

## Features

- Simultaneous live following of `/var/log/mail.log` and
  `/var/log/rspamd/rspamd.log`, each with independent inode/offset state.
- Replay of plain and `.gz` historical logs without converting historical files
  into live-follow sources.
- Queue-ID / Message-ID correlation, including `resent-message-id` aliases and
  `spamd ... aka ...` evidence.
- Postfix envelope, client, SMTP/LMTP delivery, DSN, milter rejection, SMTP
  rejection, TLS and SASL parsing.
- Postscreen connection, DNSBL rank and DNSBL rejection parsing.
- SpamAssassin verdict/score/rule/autolearn parsing, including standard
  `X-Spam-Status` correlation when logged by Postfix.
- Native Rspamd file-log parsing for Queue-ID/Message-ID, action, score/required
  score, symbols, forced action, settings ID, timing, DNS requests, digest,
  client IP, sender and recipients. Standard `X-Rspamd-*` and
  `X-Spamd-Result` headers provide redundant evidence.
- Standard ClamAV milter `X-Virus-Status` correlation plus native
  `clamav-milter` log support.
- OpenDKIM, OpenDMARC and Dovecot login/LMTP support.
- SQLite WAL mode, indexes, event deduplication and state recovery after service
  restarts.
- Configurable retention of original raw log text without deleting normalized
  historical events or statistics.
- Search by Queue-ID, Message-ID, sender or recipient.
- Inbound/outbound/internal/relay direction classification.
- Explicit/manual 9.4 import/migration tooling that does not modify original
  legacy files.
- Historical Queue-ID reuse support through internal generation identities while
  preserving the original displayed/searchable Queue-ID.
- Parser coverage tooling for discovering unsupported log formats.
- Responsive HTML5 web interface, JSON API and metrics endpoint.
- systemd `Type=simple` services with no custom daemonization or PID file.
- PSGI binds to `127.0.0.1` by default for reverse-proxy deployment.

## Standard filter headers

The public parser intentionally depends on standard engine headers rather than
site-specific renames:

- SpamAssassin: `X-Spam-Status`;
- Rspamd: `X-Rspamd-Action`, `X-Rspamd-Score`, `X-Spamd-Result` and native
  Rspamd file logs;
- ClamAV milter: `X-Virus-Status`.

Locally renamed/private headers are not embedded in the public source.

## Debian dependencies

Installing with APT is recommended. Replace `VERSION` with the downloaded
Debian package version:

```sh
apt install ./sendmailanalyzer_VERSION_all.deb
```

allows APT to resolve the runtime dependencies, including Perl, DBI/SQLite,
Plack, URI, ACL and systemd packages. `apache2` and `rsyslog` are recommended
rather than forced dependencies. See `docs/DEPENDENCIES.md`.

## Commands

- `sa10_collect` — live collector and replay engine.
- `sa10_coverage` — parser coverage analyzer.
- `sa10_migration_check` — non-destructive 9.4 migration preflight.
- `sa10_migrate` — explicit cold legacy migration/replay workflow.
- `sa10_migration_audit` — exact audit of imported legacy days.
- `sa10_rspamd_audit` — compares Postfix and native Rspamd identities/actions/scores.
- `sa10_import_legacy` — explicit 9.4 `.dat` importer.
- `sa10_parse` — diagnostic JSON parsing output.
- `sa10_db` — SQLite/query CLI.
- `sa10_selftest` — pre-start installation/configuration validation.
- `sa10_reconcile` — legacy/v10 daily reconciliation helper.
- `sa10_web` — starts PSGI using `BIND_HOST`/`BIND_PORT`.
- `sa10_prepare_logs` — idempotently prepares least-privilege log access.
- `sa10_upgrade_from_94` — explicit legacy upgrade helper.
- `sa10_apache_upgrade` — normalizes existing Apache integration while
  preserving custom routes and `Require` rules.
- `sa10_retire_94` — explicit legacy retirement helper with rollback backup.

## Installation and configuration

See `docs/INSTALL.md`. `/etc/sendmailanalyzer.conf` contains English inline help
for every parameter, while `docs/CONFIGURATION.md` provides the complete
reference. During v10 upgrades the package preserves all existing values and
only adds newly required parameters that are missing.

## Building the Debian package

The source archive includes a complete `debian/` directory. With build
dependencies installed:

```sh
dpkg-buildpackage -us -uc -b
```

The package is written to the parent directory. `debian/README.source` also
documents the reproducible convenience builder in `scripts/build-deb.sh`.

## SendmailAnalyzer 9.4 migration policy

See `docs/MIGRATION-9.4.md`. Current package revisions do **not** automatically
import or retire 9.4. Existing v10 SQLite history is preserved as authoritative,
and a fresh installation starts collecting new data from configured log files.
Legacy helpers remain available only for deliberate manual operations.

## Authorship, license and credits

**SendmailAnalyzer 10** is created and maintained by
**Nazcar <nazcar@almogavers.net>**.

SendmailAnalyzer 10 is distributed under **GPL-3.0-or-later**. The original
**SendmailAnalyzer** project was created by **Gilles Darold** (copyright
2002–2020), and its concepts and historical reporting behavior are the
compatibility reference for this modernization.

The SendmailAnalyzer 10 public source and package use their own text-based
branding and do not redistribute the historical Sendmail "Bat" logo.
