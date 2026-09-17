# SendmailAnalyzer 10 design

The architectural boundary is intentionally simple and stable:

```text
raw log -> parser event -> correlation -> classification -> SQLite -> API/web
```

The reporting layer never reparses log text. It consumes normalized facts from
SQLite.

## Semantics

Filter-engine verdicts are evidence, not final MTA disposition. SendmailAnalyzer
stores these concepts separately:

- SpamAssassin detection, score and rules;
- Rspamd action, score and symbols;
- DKIM and DMARC results;
- antivirus status;
- Postfix transport status;
- final rejection/delivery state.

This accurately represents cases where SpamAssassin detects spam, Rspamd takes
no blocking action, and Postfix still delivers the message.

## Persistent state

SQLite contains, among other tables:

- `messages`: consolidated state per internal message identity/Queue-ID;
- `recipients`: per-recipient delivery results;
- `events`: normalized evidence and, temporarily, the original raw line;
- `auth_events`: authentication events;
- `tls_events`: TLS sessions;
- `collector_state`: per-source inode/offset state;
- `message_ids`: canonical and alternate Message-ID aliases;
- `legacy_aggregates`: bounded historical aggregate counters where applicable.

The database uses WAL mode, parameterized queries, indexes and idempotent event
deduplication.
