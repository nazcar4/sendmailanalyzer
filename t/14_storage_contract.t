use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $f="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm"; open my $fh,'<',$f or die $!; local $/; my $s=<$fh>; close $fh;
unlike($s,qr/CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_mid/,'Message-ID is not unique');
like($s,qr/CREATE INDEX IF NOT EXISTS idx_messages_mid/,'Message-ID has non-unique correlation index');
like($s,qr/schema_version','8'/,'schema v8 migration present'); like($s,qr/display_queue_id/,'schema v8 preserves original Queue-ID display for qualified historical generations');
for my $c (qw(rspamd_required_score rspamd_forced_action rspamd_settings_id rspamd_scan_time_ms rspamd_dns_requests)) { like($s,qr/\b\Q$c\E\b/,"schema persists $c"); }
like($s,qr/sub link_message_id/,'event correlation backfill available');
like($s,qr/sub load_classifier_message/,'classifier hydration available');
unlike($s,qr/for my \$rcpt \(\@\{\$m->\{recipients\}/,'message upsert no longer creates recipient placeholders');
like($s,qr/removed=MAX\(messages\.removed,excluded\.removed\)/,'removed state is monotonic');
done_testing;
