# Roadmap after SendmailAnalyzer 10.0

The 10.0.x series establishes the modernization core: modular parsers, SQLite,
coverage auditing, web/API reporting, systemd services and Debian packaging.

Compatible future improvements may include:

- extending parsers from new `unknown` patterns reported by `sa10_coverage`;
- configurable anonymization of exported historical data;
- broader modern Sendmail MTA support (v10 is Postfix-first);
- additional CSV/JSON exports;
- signed Debian packages and an APT repository;
- additional Prometheus metrics based on operational demand;
- CI across supported Debian/Perl/SQLite combinations.
