# SendmailAnalyzer 10 configuration

The main configuration file is `/etc/sendmailanalyzer.conf`. It uses simple
`PARAMETER value` lines; comments begin with `#`.

After any change, run:

```sh
/usr/bin/sa10_selftest --config /etc/sendmailanalyzer.conf
```

SendmailAnalyzer never requires Postfix, Rspamd, Dovecot, rsyslog, SSH,
firewall or network services to be restarted. If only collector parameters
change, restart `sendmailanalyzer-collector.service`. If only `BIND_HOST` or
`BIND_PORT` changes, restart `sendmailanalyzer-web.service`.

## Parameters

| Parameter | Purpose | Typical value |
|---|---|---|
| `LOG_FILE` | Primary mail log followed in real time. | `/var/log/mail.log` |
| `RSPAMD_LOG_FILE` | Native Rspamd log used for actions, scores, symbols and metadata. | `/var/log/rspamd/rspamd.log` |
| `DB_FILE` | Persistent v10 SQLite database. | `/var/lib/sendmailanalyzer/sendmailanalyzer.sqlite3` |
| `STATE_FILE` | Compatibility placeholder; current offsets are stored in SQLite. | Leave unchanged |
| `LEGACY_DATA_DIR` | 9.4 flat data used only by explicit/manual migration tools. | `/usr/local/sendmailanalyzer/data` |
| `LOCAL_DOMAINS` | Comma-separated local domains used for traffic direction. | `example.org,mail.example.org` |
| `HOSTNAME` | Optional logical host name for events; the system host name is used when omitted. | empty |
| `BIND_HOST` | Address where Plack listens. Use loopback behind a reverse proxy. | `127.0.0.1` |
| `BIND_PORT` | Local PSGI web port. | `9080` |
| `RAW_RETENTION_DAYS` | Raw log retention in days. Structured data is never removed by this setting. `0` disables pruning. | `31` |
| `WEB_PAGE_SIZE` | Default number of rows in web listings. | `100` |
| `MEMORY_MESSAGE_LIMIT` | Approximate classifier message-cache limit. | `10000` |

## Log permissions

The collector runs as `sendmailanalyzer`, never as root. The package depends on
`acl` and runs `sa10_prepare_logs` during installation.

For `LOG_FILE` (normally `/var/log/mail.log`), read access is applied to the
current file and `mail.log.N`/`.gz` rotations. The service account is also added
to Debian's `adm` group, which is the normal mechanism for future
`root:adm 0640` mail logs.

For Rspamd, only directory traversal and read access to `rspamd.log*`/`.gz` are
granted. A default ACL on the log directory allows future rotations to inherit
the required read access. The collector receives neither write permission nor
general directory-listing access.

Reapply or verify the policy idempotently with:

```sh
/usr/bin/sa10_prepare_logs /etc/sendmailanalyzer.conf
```

## Local domains

`LOCAL_DOMAINS` is central to direction classification. Example:

```text
LOCAL_DOMAINS example.org,mail.example.org
```

Direction is interpreted as:

- external -> local: `inbound`;
- local -> external: `outbound`;
- local -> local: `internal`;
- external -> external: `relay`.

## Web interface behind Apache

With Apache as a reverse proxy, keep:

```text
BIND_HOST 127.0.0.1
BIND_PORT 9080
```

The application validates and understands `X-Forwarded-Prefix`, allowing it to
be published below a path such as `/reports/` without generating incorrect
absolute links.

## Raw retention

`RAW_RETENTION_DAYS` affects only the original log line stored in `events.raw`.
When it expires, event type, timestamp, Queue-ID, Message-ID, scores, statuses,
recipients and all other structured fields remain available. Historical
statistics are therefore preserved.

## Quick validation

```sh
/usr/bin/sa10_selftest --config /etc/sendmailanalyzer.conf
runuser -u sendmailanalyzer -- /usr/bin/sa10_db \
  --config /etc/sendmailanalyzer.conf --cmd quick-check
```

Both commands should succeed before a new installation is considered ready.

## Upgrades from earlier 10.x revisions

`/etc/sendmailanalyzer.conf` is a Debian conffile. Existing administrator values
are preserved during upgrades. Before unpacking a new revision, `preinst` also
creates a dated backup under `/var/backups/sendmailanalyzer/`.

After unpacking, `postinst` compares the active configuration with the complete
template installed at
`/usr/share/sendmailanalyzer/defaults/sendmailanalyzer.conf`. If a new mandatory
parameter is missing, only that parameter and its default value are appended.
Existing values are never overwritten by this merge.

This preserves local domains, log paths, listening port, retention policy and
other site-specific settings across v10 upgrades.

## Site-local drop-ins and renamed milter headers

`CONFIG_DIR` defaults to `/etc/sendmailanalyzer.d`. Files ending in `.conf` are
loaded in lexical order after `/etc/sendmailanalyzer.conf`; later values override
earlier scalar settings. The Debian package deliberately does not own files in
this directory, so deployment-specific settings can survive upgrades without
being committed to the public source tree.

Two repeatable directives are available for installations that rename headers
with Postfix `milter_header_checks` or equivalent filtering:

```text
HEADER_ROUTE X-Custom-Rspamd-Status rspamd
HEADER_ROUTE X-Custom-SpamAssassin-Status spamassassin
HEADER_ROUTE X-Custom-Virus-Status clamav
HEADER_IGNORE X-Custom-Informational
```

`HEADER_ROUTE` accepts the engines `rspamd`, `spamassassin`, and `clamav`.
Matching is case-insensitive. On a Postfix `milter-header-replace` log line, a
configured rewritten destination header takes precedence over the original
header when the engine is ambiguous. This lets Rspamd and SpamAssassin both use
`X-Spam-Status` while still being attributed correctly after a local rewrite.

`HEADER_IGNORE` is for deployment-specific informational headers that should not
count as unknown coverage. Do not use it for a result header that carries a
security verdict you want SendmailAnalyzer to record.

Keep real domains, private header names, credentials and other deployment-only
values in the drop-in directory rather than in the source repository.
