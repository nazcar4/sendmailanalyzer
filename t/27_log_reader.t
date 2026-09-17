use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use FindBin;
use lib "$FindBin::Bin/../lib"; use SendmailAnalyzer::LogReader; use IO::Compress::Gzip qw(gzip $GzipError);
my $tmp=tempdir(CLEANUP=>1); my $plain="$tmp/mail.log"; my $gz="$tmp/rspamd.log.1.gz";
open my $p,'>',$plain or die $!; print $p "one\ntwo\n"; close $p;
gzip \"three\nfour\n" => $gz or die "gzip failed: $GzipError";
my ($fh,$c)=SendmailAnalyzer::LogReader->open_reader($plain); is($c,0,'plain source'); is(join('',<$fh>),"one\ntwo\n",'plain content'); close $fh;
($fh,$c)=SendmailAnalyzer::LogReader->open_reader($gz); is($c,1,'gzip source'); is(join('',<$fh>),"three\nfour\n",'gzip content'); close $fh;
done_testing;
