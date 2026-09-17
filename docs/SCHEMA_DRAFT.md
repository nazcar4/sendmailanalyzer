# SQLite schema notes

The effective schema is created and migrated by
`SendmailAnalyzer::Storage::SQLite`. This document records design intent rather
than replacing the executable schema code.

Core entities include `messages`, `recipients`, `events`, `auth_events`,
`tls_events`, `collector_state`, `message_ids` and bounded legacy aggregates.

Message-ID has a non-unique index by design. Queue-ID reuse across historical
generations can be internally disambiguated while preserving the original
visible Queue-ID.

Schema additions across v10 have remained additive where possible. Rspamd
native metadata includes required score, forced action, settings ID, scan time
and DNS-request count; symbol details and other evidence remain available in
structured event JSON.

`RAW_RETENTION_DAYS` deletes only the original `events.raw` text. It never
removes the normalized event or its historical statistics.
