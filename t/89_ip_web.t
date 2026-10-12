use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);

my $f="$Bin/../web/sendmailanalyzer.psgi";
open my $fh,'<:encoding(UTF-8)',$f or die $!;
local $/;
my $s=<$fh>;
close $fh;

like(
    $s,
    qr{side_link\(\$prefix,'/ips','IPs'},
    'sidebar exposes IP statistics'
);

like(
    $s,
    qr{\$path eq '/api/top/ips'},
    'IP statistics JSON API exists'
);

like(
    $s,
    qr/top_ips\(\$limit,\$from,\$to\)/,
    'IP API supports limit and time range'
);

like(
    $s,
    qr{\$path eq '/ips'},
    'IP statistics HTML page exists'
);

like(
    $s,
    qr/Combined SMTP client, authentication and TLS activity/,
    'IP page explains combined activity'
);

for my $heading (
    'Activity',
    'Messages',
    'Inbound',
    'Outbound',
    'Internal',
    'Relay',
    'Unknown',
    'Rejected',
    'Spam',
    'Auth OK',
    'Auth failures',
    'TLS',
    'Last activity'
) {
    like($s,qr/\Q$heading\E/,"IP page exposes $heading");
}

like(
    $s,
    qr/Activity = messages \+ authentication events \+ TLS connections/,
    'activity ranking semantics are documented'
);

unlike(
    $s,
    qr{(?:ipinfo\.io|ip-api\.com|whoisxmlapi|api\.ipgeolocation|geoiplookup)},
    'IP page has no external IP lookup dependency'
);

done_testing;
