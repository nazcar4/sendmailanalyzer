use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
sub slurp { my($f)=@_; open my $h,'<:encoding(UTF-8)',$f or die $!; local $/; <$h> }
my $w=slurp("$Bin/../web/sendmailanalyzer.psgi");
like($w,qr/unknown=>'Unclassified'/,'direction table labels unknown as Unclassified');
like($w,qr/\['unknown','pie-unknown','Unclassified'\]/,'donut includes unknown direction');
like($w,qr/\['unknown','Unclassified'\]/,'classic flow table includes unknown direction');
like($w,qr/\['unknown','line-unknown'\]/,'hourly flow graph includes unknown messages');
like($w,qr/\['unknown_bytes','line-unknown'\]/,'hourly size graph includes unknown bytes');
like($w,qr{/direction/unknown},'sidebar and route expose unclassified historical messages');
like($w,qr/\?date='\.\$ds\.'&scope=month&hour=/,'month links open a real monthly scope and reset hour filter');
like($w,qr/\?date='\.\$date\.'&hour=/,'day reset link remains explicit');
my $s=slurp("$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm");
like($s,qr/direction IS NULL OR direction='' OR direction='unknown' THEN 1 ELSE 0 END\) unknown/,'hourly storage exposes unknown count');
like($s,qr/direction IS NULL OR direction='' OR direction='unknown' THEN size ELSE 0 END\),0\) unknown_bytes/,'hourly storage exposes unknown bytes');
like($s,qr/inbound\|outbound\|internal\|relay\|unknown/,'message filtering accepts unknown direction');
done_testing;
