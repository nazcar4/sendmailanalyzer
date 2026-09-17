use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $f="$Bin/../web/sendmailanalyzer.psgi"; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; my $s=<$fh>;
like($s,qr{href="'\.h\(u\(\$prefix,'/api/stats'\)\)\.\'" target="_blank" rel="noopener noreferrer"},'API JSON opens in a new tab safely');
like($s,qr{href="'\.h\(u\(\$prefix,'/metrics'\)\)\.\'" target="_blank" rel="noopener noreferrer"},'Metrics opens in a new tab safely');
like($s,qr/API JSON ↗/,'API JSON visually indicates external/new-tab navigation');
like($s,qr/Metrics ↗/,'Metrics visually indicates external/new-tab navigation');
done_testing;
