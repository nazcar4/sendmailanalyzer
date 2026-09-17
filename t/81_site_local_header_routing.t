use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use SendmailAnalyzer::Config;
use SendmailAnalyzer::Parser;
use SendmailAnalyzer::Coverage;

my $dir=tempdir(CLEANUP=>1);
my $drop="$dir/conf.d";
mkdir $drop or die $!;
my $base="$dir/sendmailanalyzer.conf";
open my $fh,'>',$base or die $!;
print $fh "CONFIG_DIR $drop\nLOCAL_DOMAINS example.test\n";
close $fh;
open $fh,'>',"$drop/90-local.conf" or die $!;
print $fh <<'CONF';
HEADER_ROUTE X-Custom-Rspamd-Status rspamd
HEADER_ROUTE X-Custom-SpamAssassin-Status spamassassin
HEADER_ROUTE X-Custom-Virus-Status clamav
HEADER_IGNORE X-Custom-Informational
CONF
close $fh;

my $cfg=SendmailAnalyzer::Config->load($base);
is($cfg->{HEADER_ROUTES}{'x-custom-rspamd-status'},'rspamd','Rspamd custom header route loaded');
is($cfg->{HEADER_ROUTES}{'x-custom-spamassassin-status'},'spamassassin','SpamAssassin custom header route loaded');
is($cfg->{HEADER_ROUTES}{'x-custom-virus-status'},'clamav','ClamAV custom header route loaded');
ok($cfg->{HEADER_IGNORE}{'x-custom-informational'},'custom informational header ignore loaded');

my %opt=(year=>2026,header_routes=>$cfg->{HEADER_ROUTES},header_ignore=>$cfg->{HEADER_IGNORE});
my $compact='Sep 16 23:00:01 mail postfix/cleanup[100]: ABC123: milter-header-replace: header X-Spam-Status: No, score=-2.29 from mx.example.test[192.0.2.10]; from=<a@example.test> to=<b@example.test>: X-Custom-Rspamd-Status: No, score=-2.29';
my $e=SendmailAnalyzer::Parser->parse_line($compact,%opt);
ok($e,'routed compact X-Spam-Status parsed');
my $h=$e->as_hash;
is($h->{source},'rspamd','custom destination route attributes compact status to Rspamd');
is($h->{type},'score','Rspamd routed status is a score event');
is(0+$h->{score},-2.29,'Rspamd routed score retained');

my $detailed='Sep 16 23:00:02 mail postfix/cleanup[101]: DEF456: milter-header-replace: header X-Spam-Status: Yes, score=7.5 required=5.0 tests=GTUBE,TEST_RULE from mx.example.test[192.0.2.11]; from=<a@example.test> to=<b@example.test>: X-Custom-SpamAssassin-Status: Yes, score=7.5 required=5.0';
$e=SendmailAnalyzer::Parser->parse_line($detailed,%opt);
ok($e,'routed detailed X-Spam-Status parsed');
$h=$e->as_hash;
is($h->{source},'spamassassin','custom destination route attributes detailed status to SpamAssassin');
is(0+$h->{required_score},5,'SpamAssassin threshold retained');

# No custom routing: portable standard forms still disambiguate by content.
$e=SendmailAnalyzer::Parser->parse_line($compact,year=>2026);
is($e->as_hash->{source},'rspamd','compact standard X-Spam-Status defaults to Rspamd');
$e=SendmailAnalyzer::Parser->parse_line($detailed,year=>2026);
is($e->as_hash->{source},'spamassassin','detailed standard X-Spam-Status defaults to SpamAssassin');

my $virus='Sep 16 23:00:03 mail postfix/cleanup[102]: GHI789: milter-header-replace: header X-Virus-Status: Clean from mx.example.test[192.0.2.12]; from=<a@example.test> to=<b@example.test>: X-Custom-Virus-Status: OK';
$e=SendmailAnalyzer::Parser->parse_line($virus,%opt);
is($e->as_hash->{source},'clamav','standard ClamAV result remains portable with a custom destination header');

my $ignored='Sep 16 23:00:04 mail postfix/cleanup[103]: JKL012: prepend: header From: Test <a@example.test> from local; from=<a@example.test> to=<b@example.test>: X-Custom-Informational: yes';
ok(!SendmailAnalyzer::Parser->parse_line($ignored,%opt),'configured informational header is ignored by parser');
my $coverage=SendmailAnalyzer::Coverage->new;
is($coverage->add_line($ignored,%opt),'ignored','configured informational header counts as known ignored coverage');
is($coverage->report->{unknown},0,'ignored custom header does not lower coverage');

done_testing;
