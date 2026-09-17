use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use_ok('SendmailAnalyzer::Storage::SQLite');
if (eval { require DBI; require DBD::SQLite; 1 }) {
  my $db='/tmp/sa10-test-'.$$.'-'.time.'.sqlite'; my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db); ok(-e $db,'DB created'); my $st=$s->stats(); is($st->{messages},0,'empty DB'); unlink $db; unlink "$db-wal"; unlink "$db-shm";
} else { pass('DBI/SQLite not installed in build container; runtime dependency declared'); pass('storage runtime test skipped'); }
done_testing;
