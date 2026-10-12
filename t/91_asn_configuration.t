use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

use lib "$Bin/../lib";
use SendmailAnalyzer::Config;

my $defaults=SendmailAnalyzer::Config->defaults;

ok(
    exists($defaults->{ASN_DB_FILE}),
    'ASN_DB_FILE exists in configuration defaults'
);

is(
    $defaults->{ASN_DB_FILE},
    '',
    'ASN enrichment is disabled by default'
);

my $template="$Bin/../config/sendmailanalyzer.conf";

open my $tfh,'<:encoding(UTF-8)',$template or die $!;
my $template_text;
{
    local $/;
    $template_text=<$tfh>;
}
close $tfh;

like(
    $template_text,
    qr/^# ASN_DB_FILE$/m,
    'public configuration documents ASN_DB_FILE'
);

like(
    $template_text,
    qr{^# ASN_DB_FILE /usr/share/GeoIP/GeoLite2-ASN\.mmdb$}m,
    'public configuration includes a local GeoLite2 ASN example'
);

unlike(
    $template_text,
    qr{^ASN_DB_FILE\s+\S+}m,
    'public configuration does not enable ASN by default'
);

my $tmp=tempdir(CLEANUP=>1);
my $drop="$tmp/drop";

mkdir $drop or die $!;

my $main="$tmp/sendmailanalyzer.conf";

open my $fh,'>:encoding(UTF-8)',$main or die $!;
print {$fh} "CONFIG_DIR $drop\n";
print {$fh} "ASN_DB_FILE /tmp/main-asn.mmdb\n";
close $fh;

my $cfg=SendmailAnalyzer::Config->load($main);

is(
    $cfg->{ASN_DB_FILE},
    '/tmp/main-asn.mmdb',
    'main configuration loads ASN_DB_FILE'
);

open my $df,'>:encoding(UTF-8)',"$drop/90-asn.conf" or die $!;
print {$df} "ASN_DB_FILE /tmp/dropin-asn.mmdb\n";
close $df;

$cfg=SendmailAnalyzer::Config->load($main);

is(
    $cfg->{ASN_DB_FILE},
    '/tmp/dropin-asn.mmdb',
    'site-local drop-in overrides ASN_DB_FILE'
);

done_testing;
