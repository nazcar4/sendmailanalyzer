# Security model

- The collector and web service run as the unprivileged `sendmailanalyzer`
  account.
- The package grants only the log traversal/read permissions required for the
  configured sources; it does not run the collector as root.
- The PSGI service binds to `127.0.0.1` by default and is intended to sit behind
  a reverse proxy with explicit access control.
- Web responses use a restrictive Content-Security-Policy and security headers;
  the application does not require external JavaScript libraries.
- SQLite access is parameterized. The web application is read-only.
- API message-list limits are bounded to reduce accidental or abusive large
  queries.
- Package upgrades preserve and validate the existing v10 SQLite database,
  create rollback snapshots, and restore previous state on validation failure
  where possible.
- On a running Debian/systemd host, the package enables/restarts only its own
  collector and web services after successful validation. It does not restart
  Postfix, Rspamd, Dovecot, rsyslog, SSH, firewall or network services.
- Standard engine headers are parsed (`X-Spam-Status`, `X-Rspamd-*`,
  `X-Spamd-Result`, `X-Virus-Status`); site-specific renamed headers are not
  embedded in the public parser.
