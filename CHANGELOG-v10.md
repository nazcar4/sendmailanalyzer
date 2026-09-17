# SendmailAnalyzer 10 changelog

## Debian revision 10.0.16-16 — publication hygiene

- Replace the remaining production-derived Queue-IDs, Message-IDs, process IDs,
  Rspamd digests and short host labels in public parser fixtures with explicitly
  synthetic values while preserving parser edge cases.
- Rename deployment-oriented test filenames to neutral functional names.
- Make package-installation examples revision-independent so documentation does
  not become stale on every Debian revision.
- Strengthen public-release hygiene tests to reject deployment-oriented test
  names, oversized daemon PIDs in shipped examples and stale version-specific
  package-installation examples.
- Preserve the validated 10.0.16-15 runtime behavior, site-local header routing,
  authoritative v10 SQLite policy and disabled automatic 9.4 migration.

## Debian revision 10.0.16-15 — canonical public-hardening build

- Assign a unique Debian revision to the finalized public-hardening
  implementation so package builds, tags and release assets are unambiguous.
- Preserve site-local config drop-ins, generic header routing, English public
  documentation/UI, sanitized fixtures and the validated Spam/Rejections fixes.
- Establish a stable baseline for subsequent publication-hygiene work.

## Debian revision 10.0.16-14 — public-release hardening

- Replace site-specific renamed mail-filter headers with portable standard
  engine headers: SpamAssassin `X-Spam-Status`, Rspamd `X-Rspamd-*` /
  `X-Spamd-Result`, and ClamAV `X-Virus-Status`.
- Add `/etc/sendmailanalyzer.d/*.conf` site-local drop-ins plus generic
  `HEADER_ROUTE` / `HEADER_IGNORE` directives, so private Postfix header
  rewrites can be supported without forking the public package.
- Disambiguate the shared `X-Spam-Status` header: detailed SpamAssassin forms
  remain SpamAssassin, compact Rspamd forms remain Rspamd, and an explicit
  site-local route takes precedence when configured.
- Remove private deployment header names from parsers, fixtures and examples.
- Sanitize production-derived test/log fixtures with RFC example domains and
  TEST-NET addresses while preserving the original parser edge cases.
- Convert the public documentation, configuration comments and web UI text to
  English.
- Remove the packaged legacy branding image and use text-only SendmailAnalyzer
  branding, preserving the original author credit without redistributing a
  third-party logo.
- Harden `.gitignore` and add public-release hygiene regression checks to reduce
  the chance of accidentally committing databases, credentials, keys, logs or
  deployment-specific data.
- Preserve the validated 10.0.16-13 Spam/Rejections fixes and make no deliberate
  changes to production SQLite history, collector state or automatic 9.4
  migration policy.

## Debian revision 10.0.16-13

- Fix `/spam` SQL generation in `_legacy_agg_by_day()`: initialize the WHERE
  clause and bind-value arrays separately so metric names are never interpreted
  as SQL column names.
- Fix `/rejects` sorting in `top_reject_reasons()`: avoid lexical `$a` shadowing
  Perl's special sort variables.
- Add a regression test that reproduces both web failures without changing the
  database schema or historical data.

## Debian revision 10.0.16-12

- Calendar months and days with no stored data are rendered as disabled text
  instead of links to empty reports.
- Previous/Next navigation is disabled when its destination day/month has no
  stored data.
- Availability checks consider messages, events, authentication, TLS and
  historical aggregates.
- No collector, parser, Rspamd, SQLite schema, history or Apache behavior
  changes.

## Debian revision 10.0.16-11

- Clarify unavailable historical envelope senders as
  `Sender unavailable in historical data`.
- Prevent stale cross-site Apache backups from reintroducing deprecated
  `/sareport/` or `/sareport10/` routes when `/reports/` is already active.
- Preserve parser, collector, SQLite schema, historical data and monthly-report
  behavior.

## Debian revision 10.0.16-10

- Add a true monthly report from month selectors, aggregating the whole month
  and charting by day.
- Preserve unclassified historical flow in monthly totals when envelope
  metadata is unavailable.
- Keep the authoritative v10 SQLite history intact and automatic 9.4 import
  disabled.
- Remove redundant Apache `/sareport/` routes when `/reports/` is already live.

## Debian revision 10.0.16-9

- Treat an existing production v10 SQLite database as authoritative and
  preserve it across upgrades.
- Remove automatic 9.4 `.dat` / `history.tar.gz` import from `postinst`.
- Fresh installs initialize an empty SQLite database and collect configured real
  logs only.
- Create a consistent pre-upgrade SQLite rollback snapshot and restore it when
  post-install validation fails.
- Preserve configuration, collector state, custom Apache `/reports/` route,
  access controls and v10 history.
- Include historical messages with unavailable envelope metadata in flow
  totals/charts as unclassified instead of silently reporting zero.
- Clear hourly filters explicitly when changing day or month.

## Debian revision 10.0.16-8

- Stop materializing synthetic legacy `FaKe*` identities as individual SQLite
  messages/events; keep bounded day/hour historical aggregates instead.
- Preserve full detail for real Queue-ID messages.
- Add schema v8 `legacy_aggregates` and merge aggregate SMTP rejection, spam,
  virus, DSN and delivery counters into statistics.
- Add a 512 MiB temporary WAL safety guard during legacy migration and
  checkpoint after each committed day.
- Retain journald-based recovery for calendar gaps absent from 9.4 archives.

## Debian revision 10.0.16-7

- Treat upstream-generated `FaKe*` identities in legacy data as synthetic
  NOQUEUE/report identities rather than queued messages.
- Recover archive calendar gaps from retained journal mail records when
  available.
- Add period-query indexes for historical dashboard performance.
- Prefer an existing custom production report route and avoid redundant package
  `/sareport/` configuration.

## Debian revision 10.0.16-6

- Extract each monthly `history.tar.gz` only once for selected legacy members.
- Commit legacy database writes once per host/day instead of per statement,
  reducing SQLite/WAL write amplification.
- Report archive staging and per-day migration progress.
- Release temporary archive extraction data as soon as it is no longer needed.

## Debian revision 10.0.16-5

- Support legitimate Postfix Queue-ID reuse across different historical
  day/host generations.
- Keep the original Queue-ID visible/searchable while disambiguating only the
  internal historical identity.
- Merge a legacy generation into an existing native v10 Queue-ID only when its
  date matches; otherwise create a separate historical generation.
- Add schema v6 `display_queue_id`.
- Record and restore the pre-upgrade state of SendmailAnalyzer services on
  package failure.
- Support recovery from a half-configured 10.0.16-4 installation while
  preserving the valid SQLite database.

## Debian revision 10.0.16-4

- Import detailed 9.4 history from both active `.dat` files and monthly
  `history.tar.gz` archives.
- Extend migration preflight and exact audit across archived and active days.
- Recover protected history from `retired-9.4-*` backups without weakening
  backup permissions.
- Retain multi-VirtualHost Apache migration and transactional rollback behavior.

## Debian revision 10.0.16-3

- Fix Apache migration for files containing multiple VirtualHost blocks and
  preserve report aliases/`Require` ACLs independently in HTTP and HTTPS.
- Detect already-correct reverse-proxy integration to avoid duplicate routes.
- Recover missing vhost integration from package rollback material when needed.
- Merge missing 9.4 historical data into an existing v10 SQLite candidate
  atomically and audit the result before activation.
- Stop only SendmailAnalyzer collectors while creating stable migration
  snapshots; mail/network services remain untouched.
- Complete native Debian source packaging and reproducible convenience builds.
- Preserve all existing v10 configuration values across conffile upgrades.

## SendmailAnalyzer 10.0.15

- Reorganize the time selector around a compact year/month selector, centered
  day/hour navigation and a compact day calendar.
- Restore a classic report composition while keeping the modern v10 backend.
- Replace the primary bar graph with an SVG line graph for
  inbound/outbound/internal flow.
- Add delivery-direction, size-by-hour and unique sender/recipient views.
- Add read-only `hourly_flow_series()` and `unique_party_counts()` storage
  helpers without changing schema, collector or parser semantics.

## SendmailAnalyzer 10.0.14

- Introduce a classic-modern report layout with calendar/day/hour controls and
  functional sidebar categories.
- Keep all rendering local and dependency-free: HTML/CSS/SVG only.
- Continue supporting safe reverse-proxy prefixes.

## SendmailAnalyzer 10.0.13

- Expand the read-only reporting dashboard with message/status/security detail
  views and top statistics.
- Improve period filtering and navigation while retaining strict CSP/security
  headers.

## SendmailAnalyzer 10.0.12

- Improve the classic report shell, sidebar structure, responsive behavior and
  report navigation.
- Keep JSON API and metrics available as technical outputs.

## SendmailAnalyzer 10.0.11

- Expand web statistics and visual report sections while preserving a read-only
  application model.
- Add regression coverage for the visual dashboard and navigation contracts.

## SendmailAnalyzer 10.0.10

- Strengthen SQLite validation, configuration-upgrade preservation and Debian
  package transition behavior.
- Add package/runtime tests for production paths and service/database ownership.

## SendmailAnalyzer 10.0.9

- Improve migration failure recovery, service-state restoration and Apache
  upgrade safety.
- Extend exact legacy audit/reconciliation coverage.

## SendmailAnalyzer 10.0.8

- Harden legacy migration semantics, synthetic-data handling and transaction
  behavior.
- Continue expanding regression coverage for migration and rollback contracts.

## SendmailAnalyzer 10.0.7

- Improve Rspamd/native correlation and historical replay auditing.
- Strengthen parser/storage portability and UTF-8/web response handling.

## SendmailAnalyzer 10.0.6

- Replace SQLite-specific change-count assumptions with portable DBI-safe
  behavior.
- Expand self-test to exercise insertion/deduplication, Message-ID aliases and
  raw retention against a temporary SQLite database.

## SendmailAnalyzer 10.0.5 — 2026-09-16

- Add native `RSPAMD_LOG_FILE` ingestion as a second live source with independent
  inode/offset state.
- Preserve native Rspamd Queue-ID/Message-ID, action, score/required score,
  symbols/parameters, forced action, settings ID, scan time, DNS requests,
  digest, IP, user, sender and recipient lists.
- Keep standard Rspamd headers observed by Postfix as redundant evidence without
  duplicating messages or overwriting final Postfix/LMTP recipient state.
- Add `sa10_rspamd_audit`, gzip-safe historical reads and multi-source replay.
- Add migration-audit phases and schema fields for native Rspamd metadata.

## SendmailAnalyzer 10.0.4 — 2026-09-16

- Close additional Postfix/Postscreen/OpenDKIM/Dovecot patterns discovered in
  production-derived coverage fixtures (now sanitized in the public source).
- Add persistent alternate Message-ID correlation through schema v4
  `message_ids` without treating Message-ID as globally unique.
- Improve log-permission diagnostics and migration preflight safety.
- Require service-database writes to run as the `sendmailanalyzer` account.

## SendmailAnalyzer 10.0.3 — 2026-09-16

- Make classifier state resilient across restarts by hydrating Queue-ID state
  from SQLite and bounding the in-memory cache with `MEMORY_MESSAGE_LIMIT`.
- Correlate evidence by alternate Message-ID even when it arrives before the
  Queue-ID mapping.
- Expand normalized 9.4 import, reconciliation, raw-text retention, API/security
  statistics and reverse-proxy prefix support.
- Bound web message queries and strengthen self-test/security regressions.

## SendmailAnalyzer 10.0.2 — 2026-09-16

- Expand Dovecot, LMTP, Postfix TLS, peer-warning, OpenDKIM and Postscreen
  parsing.
- Improve ignored-known coverage classification for reviewed daemon/bookkeeping
  noise.
- Add regression fixtures for additional real-world log formats; public fixtures
  are now sanitized to example domains/addresses.

## SendmailAnalyzer 10.0.1 — 2026-09-16

- Expand production-oriented parser coverage for Postfix local-to-LMTP handoff,
  DNSBL, outbound TLS peers with ports, interrupted AUTH, NOQUEUE milter rejects,
  canceled queue removal and standard SpamAssassin header correlation.
- Add explicit ignored-known handling for reviewed connection/lifecycle noise.

## SendmailAnalyzer 10.0.0 — 2026-09-16

- Introduce the event-oriented parser architecture.
- Add SQLite storage with event deduplication and Queue-ID/Message-ID correlation.
- Establish the semantic rule that an engine verdict is not the final MTA
  disposition.
- Add Postfix, Postscreen, SpamAssassin, Rspamd, OpenDKIM, OpenDMARC, ClamAV and
  Dovecot parsing.
- Add inbound/outbound/internal/relay classification, legacy import tooling,
  parser coverage analysis, read-only PSGI web/API, systemd services and Debian
  packaging.

## 10.0.0_02 prototype

- Added security engines and Postscreen support.
- Expanded the initial regression suite.

## 10.0.0_01 prototype

- Initial Postfix/SpamAssassin/Rspamd event model.
