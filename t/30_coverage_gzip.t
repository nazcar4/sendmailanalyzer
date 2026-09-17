use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use FindBin; use IO::Compress::Gzip qw(gzip $GzipError);
my $tmp=tempdir(CLEANUP=>1); my $gz="$tmp/mail.log.gz"; my $line="Sep 15 10:00:00 mailhost postfix/cleanup[1]: ABC123: message-id=<m\@example.net>\n"; gzip \$line => $gz or die $GzipError;
my $script="$FindBin::Bin/../bin/sa10_coverage"; my $out=`$^X $script --year 2026 $gz 2>&1`; is($? >> 8,0,'coverage reads gzip'); like($out,qr/Lines: 1/,'one line'); like($out,qr/Parsed: 1/,'gzip line parsed'); like($out,qr/Unknown: 0/,'no unknown'); done_testing;
