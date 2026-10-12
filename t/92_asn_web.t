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
    qr/use SendmailAnalyzer::ASN/,
    'web loads optional ASN module'
);

like(
    $s,
    qr/sub asn\s*\{/,
    'web has ASN singleton'
);

like(
    $s,
    qr/db_file=>\(\$cfg->\{ASN_DB_FILE\}\|\|''\)/,
    'ASN singleton uses configured local database'
);

like(
    $s,
    qr/sub enrich_ip_rows_asn\s*\{/,
    'web has IP ASN enrichment helper'
);

like(
    $s,
    qr/\$row->\{asn\}/,
    'ASN number is attached to IP rows'
);

like(
    $s,
    qr/\$row->\{asn_organization\}/,
    'ASN organization is attached to IP rows'
);

like(
    $s,
    qr{\$path eq '/api/top/ips'},
    'IP JSON API remains present'
);

like(
    $s,
    qr/enrich_ip_rows_asn\(\$rows\)/,
    'IP results are ASN-enriched'
);

like(
    $s,
    qr/'ASN'/,
    'IP page contains ASN column'
);

like(
    $s,
    qr/'Organization'/,
    'IP page contains organization column'
);

like(
    $s,
    qr/'AS'\.h\(\$_->\{asn\}\)/,
    'ASN is rendered with AS prefix'
);

unlike(
    $s,
    qr{(?:whois|ipinfo\.io|ip-api\.com|ipgeolocation|HTTP::|LWP::|curl|wget)}i,
    'web performs no external ASN lookup'
);

done_testing;
