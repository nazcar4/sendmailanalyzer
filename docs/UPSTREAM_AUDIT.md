# Upstream audit notes

Upstream: `darold/sendmailanalyzer`, SendmailAnalyzer 9.4. Baseline reviewed: commit `43dc43ec197cbb75670560ca71971cc6ffafc416` (2026-09-13).

The current upstream design is mature but tightly coupled:

- one main Perl log parser (`sendmailanalyzer`),
- one large cache/statistics generator (`sa_cache`),
- one large CGI report program (`cgi-bin/sa_report.cgi`),
- flat-file data storage and cached aggregate reports.

The v10 intentionally does not replace all of that at once. It inserts a structured semantic boundary between parsing and reporting.

## First incompatibility fixed by design

A SpamAssassin `spamd: result: Y` line describes the SpamAssassin verdict. It does not prove that Postfix rejected the message. The v10 classifier therefore stores SpamAssassin, Rspamd and Postfix disposition independently.

## Upstream activity

The repository is not considered abandoned: upstream received a cache correctness commit in September 2026, and the maintainer has publicly stated that it is still maintained in spare time. The modernization work should therefore be designed so that isolated improvements can potentially be proposed upstream rather than assuming a hostile fork.
