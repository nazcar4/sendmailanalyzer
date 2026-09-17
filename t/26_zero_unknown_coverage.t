use strict; use warnings; use Test::More; use FindBin; use lib "$FindBin::Bin/../lib"; use SendmailAnalyzer::Parser; use SendmailAnalyzer::Coverage;
my @lines=(
'Sep 16 01:00:00 mailhost postfix/postfix-script[1]: refreshing the Postfix mail system',
'2026-09-16T01:00:01+02:00 mailhost spamd[1]: spamd: server killed by SIGTERM, shutting down',
"2026-09-16T01:00:02+02:00 mailhost opendkim[1]: ABC123: key retrieval failed (s=202505, d=relay.example.test): '202505._domainkey.relay.example.test' query timed out",
);
my $dk=SendmailAnalyzer::Parser->parse_line($lines[2]); ok($dk,'DKIM key error parsed'); my $h=$dk->as_hash; is($h->{type},'dkim_key_error','DKIM key error type'); is($h->{selector},'202505','selector'); is($h->{domain},'relay.example.test','domain');
my $c=SendmailAnalyzer::Coverage->new; $c->add_line($_,year=>2026) for @lines; my $r=$c->report; is($r->{unknown},0,'last three extended patterns no longer unknown'); is($r->{parsed},1,'DKIM error kept as structured event'); is($r->{ignored},2,'lifecycle lines consciously ignored');
done_testing;
