use strict; use warnings; use Test::More;
my $pre = do { local $/; open my $f,'<','debian/preinst' or die $!; <$f> };
my $post = do { local $/; open my $f,'<','debian/postinst' or die $!; <$f> };
my $rules = do { local $/; open my $f,'<','debian/rules' or die $!; <$f> };
like($pre, qr{/etc/sendmailanalyzer\.conf}, 'preinst backs up active v10 config');
like($pre, qr{/var/backups/sendmailanalyzer}, 'preinst uses dedicated backup directory');
like($post, qr{DEFAULT_CONF=/usr/share/sendmailanalyzer/defaults/sendmailanalyzer\.conf}, 'postinst has immutable packaged defaults');
for my $k (qw(LOG_FILE RSPAMD_LOG_FILE DB_FILE STATE_FILE LEGACY_DATA_DIR LOCAL_DOMAINS BIND_HOST BIND_PORT RAW_RETENTION_DAYS WEB_PAGE_SIZE MEMORY_MESSAGE_LIMIT)) {
    like($post, qr/\b\Q$k\E\b/, "postinst merge knows $k");
}
like($post, qr/without replacing.*existing local values/is, 'upgrade merge documents preservation semantics');
like($rules, qr{usr/share/\$\(PACKAGE\)/defaults}, 'binary package ships default template separately');
like($rules, qr{debian/preinst debian/postinst}, 'binary package installs preinst and postinst');
done_testing;
