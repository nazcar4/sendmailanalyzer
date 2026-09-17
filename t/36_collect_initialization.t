use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $f="$Bin/../bin/sa10_collect"; open my $fh,'<',$f or die $!; local $/; my $s=<$fh>; close $fh;
unlike($s,qr/my \(\@logs,\$db/,'log array is not declared inside scalar list assignment');
like($s,qr/my \@logs;\s*my \(\$db,\$follow/,'log array and scalar defaults initialized separately');
done_testing;
