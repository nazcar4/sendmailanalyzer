#!/bin/sh
# Reproducible convenience builder. Does not need debhelper and does not run tests.
# For the canonical Debian source build use: dpkg-buildpackage -us -uc -b
main() {
    ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || return 1
    OUT=${1:-"$ROOT/sendmailanalyzer_10.0.16-16_all.deb"}
    TMP=$(mktemp -d) || return 1
    trap 'rm -rf "$TMP"' HUP INT TERM
    PKG="$TMP/pkg"
    mkdir -p "$PKG/DEBIAN" "$PKG/usr/lib/sendmailanalyzer" "$PKG/usr/bin" "$PKG/etc" "$PKG/etc/sendmailanalyzer.d" \
        "$PKG/lib/systemd/system" "$PKG/usr/lib/tmpfiles.d" \
        "$PKG/usr/share/doc/sendmailanalyzer" "$PKG/usr/share/sendmailanalyzer/examples" "$PKG/usr/share/sendmailanalyzer/defaults" || return 1
    cp -a "$ROOT/lib" "$ROOT/web" "$ROOT/bin" "$PKG/usr/lib/sendmailanalyzer/" || return 1
    for b in "$ROOT"/bin/*; do ln -s "../lib/sendmailanalyzer/bin/$(basename "$b")" "$PKG/usr/bin/$(basename "$b")" || return 1; done
    cp "$ROOT/config/sendmailanalyzer.conf" "$PKG/etc/sendmailanalyzer.conf" || return 1
    cp "$ROOT/config/sendmailanalyzer-rspamd.tmpfiles" "$PKG/usr/lib/tmpfiles.d/sendmailanalyzer-rspamd.conf" || return 1
    cp "$ROOT/systemd"/*.service "$PKG/lib/systemd/system/" || return 1
    cp "$ROOT/README.md" "$ROOT/CHANGELOG-v10.md" "$ROOT/NOTICE" "$ROOT/LICENSE" "$ROOT/docs"/*.md \
       "$ROOT/config/apache2-sendmailanalyzer.conf" "$ROOT/debian/README.Debian" \
       "$PKG/usr/share/doc/sendmailanalyzer/" || return 1
    cp "$ROOT/debian/copyright" "$PKG/usr/share/doc/sendmailanalyzer/copyright" || return 1
    gzip -n -9 -c "$ROOT/debian/changelog" > "$PKG/usr/share/doc/sendmailanalyzer/changelog.Debian.gz" || return 1
    cp -a "$ROOT/examples/." "$PKG/usr/share/sendmailanalyzer/examples/" || return 1
    cp "$ROOT/config/sendmailanalyzer.conf" "$PKG/usr/share/sendmailanalyzer/defaults/sendmailanalyzer.conf" || return 1
    : > "$TMP/substvars" || return 1
    (cd "$ROOT" && dpkg-gencontrol -psendmailanalyzer -P"$PKG" -f"$TMP/files" -T"$TMP/substvars") || return 1
    cp "$ROOT/debian/conffiles" "$PKG/DEBIAN/conffiles" || return 1
    cp "$ROOT/debian/preinst" "$ROOT/debian/postinst" "$ROOT/debian/prerm" "$ROOT/debian/postrm" "$PKG/DEBIAN/" || return 1
    chmod 0755 "$PKG/DEBIAN/preinst" "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/prerm" "$PKG/DEBIAN/postrm" || return 1
    find "$PKG" -type d -exec chmod 0755 {} +
    find "$PKG/usr/lib/sendmailanalyzer/bin" -type f -exec chmod 0755 {} +
    find "$PKG/usr/lib/sendmailanalyzer/lib" -type f -exec chmod 0644 {} +
    chmod 0644 "$PKG"/lib/systemd/system/*.service "$PKG/etc/sendmailanalyzer.conf" "$PKG/usr/lib/tmpfiles.d/sendmailanalyzer-rspamd.conf"
    (cd "$PKG" && find usr lib etc -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums) || return 1
    find "$PKG" -print0 | xargs -0 touch -h -d '@1789627500' || return 1
    SOURCE_DATE_EPOCH=1789627500 dpkg-deb --build --root-owner-group "$PKG" "$OUT" || return 1
    rm -rf "$TMP"
    trap - HUP INT TERM
    return 0
}
main "$@"
