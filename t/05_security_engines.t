use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Parser;
use SendmailAnalyzer::Classifier;

my @lines = (
    'Sep 14 04:49:53 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: message-id=<20260101000000.TEST0000001@mx.example.net>',
    '2026-09-14T04:49:55.648474+02:00 mailhost opendkim[1500]: A1B2C3D4E5F: DKIM verification successful',
    '2026-09-14T04:49:55.648497+02:00 mailhost opendkim[1500]: A1B2C3D4E5F: s=mail d=example.net a=rsa-sha256 SSL',
    '2026-09-14T04:49:55.690829+02:00 mailhost opendmarc[1496]: A1B2C3D4E5F: example.net none',
    'Sep 14 04:49:53 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: milter-header-add: header X-Virus-Status: Clean from mx.example.net[198.51.100.23]; from=<scanner@example.net> to=<user@example.test> proto=ESMTP helo=<mx.example.net>',
);

my $c = SendmailAnalyzer::Classifier->new;
for my $line (@lines) {
    my $e = SendmailAnalyzer::Parser->parse_line($line);
    ok($e, "parsed security line");
    $c->add_event($e);
}
my $m = $c->finalize->{A1B2C3D4E5F};
is($m->{dkim}{verification}, 'pass', 'DKIM verification pass');
is($m->{dkim}{domain}, 'example.net', 'DKIM domain');
is($m->{dkim}{selector}, 'mail', 'DKIM selector');
is($m->{dmarc}{result}, 'none', 'DMARC result retained');
is($m->{dmarc}{domain}, 'example.net', 'DMARC domain');
is($m->{antivirus}{status}, 'clean', 'ClamAV clean');
is($m->{antivirus}{normalized_status}, 'clean', 'normalized AV status');

done_testing;
