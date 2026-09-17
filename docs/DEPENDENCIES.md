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
| `libdbi-perl` | Perl DBI layer. |
| `libdbd-sqlite3-perl` | SQLite DBI driver. |
| `libplack-perl` | PSGI server (`plackup`). |
| `liburi-perl` | Safe URL and query-parameter encoding/decoding. |

`apache2` and `rsyslog` are **Recommends** rather than hard dependencies. The
application can run without exposing the web interface through Apache and does
not impose a replacement logging policy.

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
