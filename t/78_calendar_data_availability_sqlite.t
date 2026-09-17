use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin); use File::Temp qw(tempdir);
BEGIN {
    eval { require DBI; require DBD::SQLite; 1 }
      or plan skip_all => 'DBI/DBD::SQLite not installed in build environment';
}
use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;
my $dir=tempdir(CLEANUP=>1); my $db="$dir/test.sqlite3";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);
my $d=$s->dbh;
$d->do(q{INSERT INTO messages(queue_id,first_seen,last_seen,direction) VALUES('Q1','2026-08-01T10:00:00','2026-08-01T10:00:00','inbound')});
$d->do(q{INSERT INTO events(fingerprint,timestamp,source,type,data_json) VALUES('e1','2026-08-27T12:00:00','postfix','test','{}')});
$d->do(q{INSERT INTO auth_events(timestamp,source,success,fingerprint) VALUES('2026-09-05T12:00:00','dovecot',1,'a1')});
$d->do(q{INSERT INTO tls_events(timestamp,fingerprint) VALUES('2026-10-02T12:00:00','t1')});
$d->do(q{INSERT INTO legacy_aggregates(day,hour,metric,detail,count) VALUES('2026-07-03','','smtp_rejected','',3)});
my $aug=$s->available_days_for_month('2026-08');
ok($aug->{'2026-08-01'},'message makes August 1 available');
ok($aug->{'2026-08-27'},'event makes August 27 available');
ok(!$aug->{'2026-08-02'},'empty August 2 remains unavailable');
my $months=$s->available_months_for_year('2026');
ok($months->{'2026-07'},'legacy aggregate makes July available');
ok($months->{'2026-08'},'message/event makes August available');
ok($months->{'2026-09'},'auth event makes September available');
ok($months->{'2026-10'},'TLS event makes October available');
ok(!$months->{'2026-11'},'empty November remains unavailable');
ok($s->day_has_data('2026-08-27'),'day_has_data true for populated day');
ok(!$s->day_has_data('2026-08-26'),'day_has_data false for empty day');
ok($s->month_has_data('2026-08'),'month_has_data true for populated month');
ok(!$s->month_has_data('2026-11'),'month_has_data false for empty month');
done_testing;
