use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $f="$Bin/../bin/sa10_db"; open my $fh,'<',$f or die $!; local $/; my $s=<$fh>; close $fh;
like($s,qr/\$cmd eq 'quick-check'/,'sa10_db exposes quick-check command');
like($s,qr/PRAGMA quick_check/,'quick-check runs SQLite integrity pragma');
done_testing;
