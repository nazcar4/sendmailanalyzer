#!/bin/sh
# Manual installer. The .deb is preferred because APT resolves dependencies automatically.
set -u
PREFIX=/usr/lib/sendmailanalyzer
BINDIR=/usr/bin
ETC=/etc/sendmailanalyzer.conf
STATE=/var/lib/sendmailanalyzer
SELF=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The Debian package contains the transactional 9.4/test-v10 migration logic.
# Refuse to perform a legacy in-place upgrade with the lightweight manual
# installer so it cannot leave two active installations or skip rollback data.
if [ -d /usr/local/sendmailanalyzer ] || [ -e /etc/sendmailanalyzer10.conf ] || [ -d /var/lib/sendmailanalyzer10 ]; then
    echo "Existing SendmailAnalyzer installation detected. Use the Debian package with APT: apt install ./sendmailanalyzer_VERSION_all.deb" >&2
    return 1 2>/dev/null || false
fi

if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; return 1 2>/dev/null || false; fi
for p in perl setfacl runuser plackup; do command -v "$p" >/dev/null 2>&1 || { echo "Missing $p (use the .deb to install dependencies automatically)" >&2; return 1 2>/dev/null || false; }; done

getent group sendmailanalyzer >/dev/null 2>&1 || groupadd --system sendmailanalyzer
getent passwd sendmailanalyzer >/dev/null 2>&1 || useradd --system --home-dir "$STATE" --shell /usr/sbin/nologin --gid sendmailanalyzer sendmailanalyzer
getent group adm >/dev/null 2>&1 && usermod -a -G adm sendmailanalyzer
install -d -m 0755 "$PREFIX" "$PREFIX/lib" "$PREFIX/web" "$STATE"
cp -a "$SELF/lib/." "$PREFIX/lib/"
cp -a "$SELF/web/." "$PREFIX/web/"
for b in "$SELF"/bin/*; do install -m 0755 "$b" "$BINDIR/$(basename "$b")"; done
[ -e "$ETC" ] || install -m 0644 -o root -g root "$SELF/config/sendmailanalyzer.conf" "$ETC"
install -d -m 0755 -o root -g root /etc/sendmailanalyzer.d
install -m 0644 "$SELF/systemd/sendmailanalyzer-collector.service" /etc/systemd/system/sendmailanalyzer-collector.service
install -m 0644 "$SELF/systemd/sendmailanalyzer-web.service" /etc/systemd/system/sendmailanalyzer-web.service
install -d -m 0755 /usr/lib/tmpfiles.d
install -m 0644 "$SELF/config/sendmailanalyzer-rspamd.tmpfiles" /usr/lib/tmpfiles.d/sendmailanalyzer-rspamd.conf
chown sendmailanalyzer:sendmailanalyzer "$STATE"; chmod 0750 "$STATE"
/usr/bin/sa10_prepare_logs "$ETC" || { echo "Log permission preparation failed" >&2; return 1 2>/dev/null || false; }
runuser -u sendmailanalyzer -- perl -I/usr/lib/sendmailanalyzer/lib -MSendmailAnalyzer::Storage::SQLite -e '''my $f=shift; my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$f); my ($q)=$s->dbh->selectrow_array("PRAGMA quick_check"); die "SQLite invalid\n" unless defined($q) && $q eq "ok"; $s->dbh->disconnect;''' "$STATE/sendmailanalyzer.sqlite3" || { echo "Database initialization/validation failed" >&2; return 1 2>/dev/null || false; }
/usr/bin/sa10_selftest --config "$ETC" || { echo "Self-test failed" >&2; return 1 2>/dev/null || false; }
systemctl daemon-reload
systemctl enable sendmailanalyzer-collector.service sendmailanalyzer-web.service
systemctl restart sendmailanalyzer-collector.service
systemctl restart sendmailanalyzer-web.service
echo "Installed, validated, enabled and started."
