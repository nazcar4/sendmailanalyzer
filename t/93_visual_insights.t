use strict;
use warnings;
use utf8;

use Test::More;
use FindBin qw($Bin);

sub slurp {
    my($file)=@_;
    open my $fh,'<:encoding(UTF-8)',$file or die $!;
    local $/;
    return <$fh>;
}

my $web=slurp("$Bin/../web/sendmailanalyzer.psgi");
my $storage=slurp("$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm");

like(
    $storage,
    qr/sub status_summary/,
    'storage exposes mutually exclusive message status summary'
);

like(
    $storage,
    qr/WHEN rejected=1 THEN 1/,
    'rejected status has first priority'
);

like(
    $storage,
    qr/rejected=0 AND deferred_count>0/,
    'deferred status excludes rejected messages'
);

like(
    $storage,
    qr/rejected=0\s+AND deferred_count=0\s+AND delivered_count>0/s,
    'delivered status excludes rejected and deferred messages'
);

like(
    $web,
    qr/sub status_donut/,
    'dashboard has message outcome donut renderer'
);

like(
    $web,
    qr/st\(\)->status_summary\(\$from,\$to\)/,
    'message outcome follows selected period'
);

like(
    $web,
    qr/st\(\)->month_daily_series\(substr\(\$date,0,7\)\)/,
    'monthly activity follows selected month'
);

like(
    $web,
    qr/st\(\)->hourly_series\(\$date\)/,
    'daily activity follows selected day'
);

like(
    $web,
    qr/period_chart\(\$activity,\$xkey,'Mail activity'\)/,
    'dashboard renders mail activity chart'
);

like(
    $web,
    qr/Message outcome/,
    'dashboard renders message outcome'
);

like(
    $web,
    qr/st\(\)->top_ips\(8,\$from,\$to\)/,
    'network ranking follows selected period'
);

like(
    $web,
    qr/enrich_ip_rows_asn\(\$topips\)/,
    'network ranking gets ASN enrichment'
);

like(
    $web,
    qr/Top network activity · IP \/ ASN/,
    'dashboard renders network ranking'
);

unlike(
    $web,
    qr/<script\b/i,
    'dashboard remains JavaScript-free'
);

done_testing;
