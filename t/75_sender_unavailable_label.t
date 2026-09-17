use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $file="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm";
open my $fh,'<:encoding(UTF-8)',$file or die "$file: $!"; local $/; my $s=<$fh>; close $fh;
like($s,qr/COALESCE\(NULLIF\(sender,''\),'Sender unavailable in historical data'\)/,
    'empty historical sender has an explicit non-ambiguous label');
like($s,qr/COALESCE\(NULLIF\(r\.recipient,''\),'\(empty\)'\)/,
    'recipient empty-label behavior is unchanged');
unlike($s,qr/COALESCE\(NULLIF\(sender,''\),'\(empty\)'\)/,
    'top sender no longer reports unavailable historical envelope as empty');
done_testing;
