use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::MigrationAudit;
my $tmp=tempdir(CLEANUP=>1); my $d="$tmp/mailhost/2026/09/06"; make_path($d);
open my $fh,'>',"$d/senders.dat" or die $!; print {$fh} "010000:ABC:a\@x:1:1:r\n"; close $fh;
open $fh,'>',"$d/auth.dat" or die $!; print {$fh} "010001:u:r:PLAIN:SMTP\n010001:u:r:PLAIN:SMTP\n010002:u:r:PLAIN:SMTP\n"; close $fh;
my $days=SendmailAnalyzer::MigrationAudit->discover_days($tmp);
is($days->[0]{host},'mailhost','host survives directory normalization');
is($days->[0]{date},'2026-09-06','date survives directory normalization');
is(SendmailAnalyzer::MigrationAudit->duplicate_lines("$d/auth.dat"),1,'reports exact duplicate legacy auth lines');
{
 package FakeDBH;
 sub new { bless {sql=>[]},shift }
 sub selectrow_array { my($s,$sql)=@_; push @{$s->{sql}},$sql; return 7 if $sql =~ /source='legacy'.*type='envelope'/; return 9 if $sql =~ /FROM messages WHERE first_seen/; return 0; }
}
my $db=FakeDBH->new; my $exact=SendmailAnalyzer::MigrationAudit->sqlite_counts($db,'2026-09-06',1);
is($exact->{messages},7,'exact legacy audit counts imported envelope events');
ok(grep(/source='legacy'.*type='envelope'/,@{$db->{sql}}),'exact query uses legacy envelope semantics');
$db=FakeDBH->new; my $replay=SendmailAnalyzer::MigrationAudit->sqlite_counts($db,'2026-09-07',0);
is($replay->{messages},9,'replay audit counts materialized message rows');
ok(grep(/FROM messages WHERE first_seen/,@{$db->{sql}}),'replay query uses message rows');
done_testing;
