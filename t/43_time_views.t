use strict; use warnings; use Test::More;
use FindBin qw($Bin);
my $f='lib/SendmailAnalyzer/Storage/SQLite.pm'; open my $fh,'<',$f or die $!; local $/; my $s=<$fh>;
like($s,qr/sub hourly_series/, 'hourly aggregation exists');
like($s,qr/sub monthly_series/, 'monthly aggregation exists');
like($s,qr/sub spam_daily_series/, 'spam daily aggregation exists');
like($s,qr/\$opt\{direction\}/, 'message direction filter exists');
like($s,qr/\$opt\{spam\}/, 'message spam filter exists');
like($s,qr/\$opt\{virus\}/, 'message virus filter exists');
like($s,qr/\$opt\{rejected\}/, 'message reject filter exists');

{
    my $storage_file="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm";

    open my $rfh,'<:encoding(UTF-8)',$storage_file
        or die $!;

    local $/;
    my $storage_src=<$rfh>;
    close $rfh;

    like(
        $storage_src,
        qr/sub auth_stats.*my \(\$self,\$from,\$to\).*timestamp >= \?.*timestamp <= \?/s,
        'authentication statistics accept bounded timestamps'
    );

    like(
        $storage_src,
        qr/sub tls_stats.*my \(\$self,\$from,\$to\).*timestamp >= \?.*timestamp <= \?/s,
        'TLS statistics accept bounded timestamps'
    );
}

done_testing;
