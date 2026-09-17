use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $f="$Bin/../bin/sa10_reconcile"; open my $fh,'<',$f or die $!; local $/; my $s=<$fh>; close $fh;
like($s,qr/SELECT COUNT\(\*\) FROM messages WHERE first_seen LIKE \?/,'message reconciliation uses first_seen');
unlike($s,qr/COALESCE\(last_seen,first_seen\) LIKE/,'reconciliation does not shift messages to last_seen day');
for my $m (qw(messages recipients sent spam virus dsn auth)) { like($s,qr/\b\Q$m\E\b/,"reconciliation includes $m"); }
done_testing;
