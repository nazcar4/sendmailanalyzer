use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $cfg="$Bin/../config/sendmailanalyzer.conf"; open my $fh,'<:encoding(UTF-8)',$cfg or die $!; local $/; my $s=<$fh>;
for my $k (qw(LOG_FILE RSPAMD_LOG_FILE DB_FILE STATE_FILE LEGACY_DATA_DIR LOCAL_DOMAINS BIND_HOST BIND_PORT RAW_RETENTION_DAYS WEB_PAGE_SIZE MEMORY_MESSAGE_LIMIT)) {
    like($s,qr/^# \Q$k\E\n/m,"$k has inline help");
    like($s,qr/^\Q$k\E\s+/m,"$k has a configured value");
}
like($s,qr/^# HOSTNAME\n/m,'HOSTNAME optional parameter is documented');
ok(-f "$Bin/../docs/CONFIGURATION.md",'full configuration guide exists');
open my $df,'<:encoding(UTF-8)',"$Bin/../docs/CONFIGURATION.md" or die $!; local $/; my $d=<$df>;
like($d,qr/LOCAL_DOMAINS/,'guide explains local domains');
like($d,qr/RAW_RETENTION_DAYS/,'guide explains raw retention');
like($d,qr/reverse proxy/i,'guide explains reverse proxy');
done_testing;
