# SendmailAnalyzer 10.0.16 operations

## Sources

The collector follows `LOG_FILE` and `RSPAMD_LOG_FILE` simultaneously. Each
source has its own `collector_state(source,inode,offset,updated_at)` row. After a
restart, each live file resumes from its saved offset. Historical `.1` and `.gz`
files are replay-only and never become live-follow sources.

## Permissions and rotation

The service runs as `sendmailanalyzer`, never as root.

`sa10_prepare_logs` grants read access to existing `mail.log*`/`.gz` and
`rspamd.log*`/`.gz` files. For mail logs, normal Debian rotation uses
`root:adm 0640`, and the service account belongs to `adm`. For Rspamd, a
`tmpfiles.d` rule plus a default directory ACL provide traversal and inherited
read access without granting write access or unrestricted directory listing.

Manual verification:

```sh
/usr/bin/sa10_prepare_logs /etc/sendmailanalyzer.conf
/usr/bin/sa10_selftest --config /etc/sendmailanalyzer.conf
```

## Parser coverage

`sa10_coverage` accepts one or more plain or `.gz` files and classifies every
line as `parsed`, `ignored-known` or `unknown`. `ignored-known` represents
explicitly reviewed bookkeeping/noise, not silently lost coverage.

## Rspamd

The native Rspamd file log is the richest source for symbols, settings,
forced actions, scores and timings. Standard Rspamd headers seen in Postfix
(`X-Rspamd-*` and `X-Spamd-Result`) are retained as redundant evidence.
`sa10_rspamd_audit` compares Queue-ID, Message-ID, action and score between
sources.

## SpamAssassin and ClamAV headers

Portable header correlation uses the standard headers emitted by the engines or
their milters: SpamAssassin `X-Spam-Status` and ClamAV `X-Virus-Status`. The
public parser does not depend on site-specific renamed headers.

## Collector modes

In `--follow` mode, configured live files are followed by inode/offset. In
`--replay` mode, multiple historical files can be combined. `--seed-state`
seeds only sources configured as live so systemd can continue at the correct
byte position after an explicit replay/migration workflow.

## Raw retention

`RAW_RETENTION_DAYS` sets only old `events.raw` fields to `NULL`. Structured
JSON/event data, correlation and statistics remain in SQLite.

## API and metrics

- `/api/stats`
- `/api/messages?q=`
- `/api/message/<queue-id>`
- `/api/series`
- `/api/top/senders`
- `/api/top/recipients`
- `/api/security`
- `/metrics`

The web interface opens **API JSON** and **Metrics** in a separate tab to keep
the main report context intact.

## Message-ID

`messages.message_id` is not globally unique. The `message_ids` table stores
canonical and alternate aliases (including `resent-message-id` and
`spamd ... aka ...`) so evidence that arrives before a Queue-ID can be
correlated later.
