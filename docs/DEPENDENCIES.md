# SendmailAnalyzer 10.0.16 dependencies

The recommended installation method is APT:

```sh
apt install ./sendmailanalyzer_VERSION_all.deb
```

APT reads package metadata and installs missing dependencies automatically. No
manual CPAN installation is required.

## Runtime dependencies

| Debian package | Purpose |
|---|---|
| `perl` | Runtime and core modules such as `JSON::PP`, `IO::Uncompress::Gunzip` and `Digest::SHA`. |
| `passwd` | Service user/group management (`useradd`, `groupadd`, `usermod`). |
| `acl` | `setfacl` for least-privilege access to current and rotated logs. |
| `util-linux` | `runuser`, used so service SQLite writes occur as the service account. |
| `systemd` | Collector/web units and `systemd-tmpfiles`. |
| `tar` | Manual legacy 9.4 archive tooling and source/package operations. |
| `gzip` | Compressed historical log support and reproducible documentation/package output. |
| `debconf` | Interactive/preseedable dedicated reporting-site configuration during Debian installation. |
| `libdbi-perl` | Perl DBI layer. |
| `libdbd-sqlite3-perl` | SQLite DBI driver. |
| `libplack-perl` | PSGI server (`plackup`). |
| `liburi-perl` | Safe URL and query-parameter encoding/decoding. |

`apache2`, `apache2-utils`, `bind9-utils`, `openssl` and `rsyslog` are
**Recommends** rather than hard dependencies. Apache provides the reverse
proxy, `apache2-utils` provides `htpasswd`, BIND utilities provide local zone
validation/signing tools when local DNS management is applicable, and OpenSSL
validates certificate expiry and hostname coverage. The core analyzer can run
without publishing its web interface or managing local DNS.

## Optional ASN enrichment

ASN enrichment for IP statistics is optional.

When `ASN_DB_FILE` points to a local MaxMind GeoLite2 ASN database,
SendmailAnalyzer can display the autonomous system number and organization for
IP addresses.

The optional Perl reader is available on Debian as
`libmaxmind-db-reader-perl`.

The Debian package declares this module as `Suggests`, not as a mandatory
runtime dependency. SendmailAnalyzer continues to work normally when the module
or ASN database is absent.

The ASN database itself is not bundled with SendmailAnalyzer. The administrator
must provide a compatible local `.mmdb` database and configure its path with
`ASN_DB_FILE`.

ASN lookups are entirely local. SendmailAnalyzer performs no Whois query, HTTP
request, external API call or other network lookup for ASN enrichment.

## Build dependencies

The source tree contains complete `debian/` metadata. Install the
`Build-Depends` declared in `debian/control` and run:

```sh
dpkg-buildpackage -us -uc -b
```

The package is written to the parent directory, for example:

```text
../sendmailanalyzer_VERSION_all.deb
```
