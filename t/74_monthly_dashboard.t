use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
sub slurp { my($f)=@_; open my $h,'<:encoding(UTF-8)',$f or die $!; local $/; <$h> }
my $w=slurp("$Bin/../web/sendmailanalyzer.psgi");
like($w,qr/scope=month&hour=/,'month selector explicitly enters monthly scope');
like($w,qr/Monthly Report/,'monthly console is visibly labelled');
like($w,qr/period_scope eq 'month'/,'root route distinguishes monthly scope');
like($w,qr/month_daily_flow_series/,'monthly dashboard uses daily flow series');
like($w,qr/Full month/,'monthly report identifies whole-month coverage');
like($w,qr/Select a calendar day/,'monthly mode guides user back to daily detail');
my $s=slurp("$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm");
like($s,qr/sub month_daily_flow_series/,'storage provides daily flow data for a selected month');
like($s,qr/direction IS NULL OR direction='' OR direction='unknown' THEN 1 ELSE 0 END\) unknown/,'monthly flow keeps unknown historical direction');
done_testing;
