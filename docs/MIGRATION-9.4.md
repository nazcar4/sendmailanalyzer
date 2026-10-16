# SendmailAnalyzer 9.4 migration policy since 10.0.16-9

Normal installations and v10 upgrades **do not automatically import or retire**
SendmailAnalyzer 9.4 data. An existing v10 SQLite database is authoritative and
is preserved at `/var/lib/sendmailanalyzer/sendmailanalyzer.sqlite3`.

A fresh installation creates an empty v10 SQLite database and starts collecting
only the configured real log sources.

## Legacy tools

`sa10_upgrade_from_94`, `sa10_migration_check`, `sa10_migration_audit`,
`sa10_import_legacy` and `sa10_retire_94` remain available only for deliberate,
manual legacy operations. Package `postinst` does not invoke them automatically.

Before any manual 9.4 data operation, create an independent backup and validate
the candidate database before replacing production data.

## Normal v10 upgrades

During a standard v10 upgrade:

1. `preinst` stops only the SendmailAnalyzer services required to obtain a
   consistent snapshot.
2. It checkpoints WAL and runs `PRAGMA quick_check` against the existing SQLite
   database.
3. It retains rollback copies of SQLite, configuration and collector state.
4. `postinst` keeps SQLite at the same pathname and applies only compatible,
   additive v10 schema migrations through the storage layer.
5. It runs the project self-test and SQLite quick-check.
6. It restores the SendmailAnalyzer services that should be active.
7. If validation fails, the installer attempts to restore the pre-upgrade
   snapshot and prior service state.

Historical data rebuilt from real logs is considered authoritative. Package
upgrades do not reinterpret 9.4 `.dat` files or `history.tar.gz` archives.

## Apache

The preferred production layout since Debian revision `10.0.16-19` is a
dedicated HTTPS reporting subdomain reverse-proxied at `/` to the local PSGI
service. Existing dedicated root-proxy installations are recognized as valid
production integrations and are preserved unchanged when possible.

Historical path-based `/reports/` integrations remain detectable for
compatibility. Deprecated `/sareport/` and `/sareport10/` routes are not
revived from stale backups, and existing access-control rules remain protected
during migration decisions.

## Queue-ID handling

v10 preserves the original visible Queue-ID and can internally disambiguate
historical reuse. Normal upgrades never re-import legacy Queue-ID generations.
