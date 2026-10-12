use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use POSIX qw(strftime);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/health.sqlite3";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

my $now=strftime('%Y-%m-%dT%H:%M:%S',localtime);
my $now_with_zone=strftime('%Y-%m-%dT%H:%M:%S%z',localtime);

$s->dbh->do(
    q{INSERT INTO messages(queue_id,first_seen,last_seen,sender,direction)
      VALUES(?,?,?,?,?)},
    undef,'HEALTH001',$now,$now,'sender@example.test','unknown'
);

$s->dbh->do(
    q{INSERT INTO events(fingerprint,timestamp,host,queue_id,source,type,data_json,raw)
      VALUES(?,?,?,?,?,?,?,?)},
    undef,'health-event-1',$now,'mailhost','HEALTH001',
    'postfix','message_id','{}','synthetic health fixture'
);

$s->dbh->do(
    q{INSERT INTO recipients(queue_id,recipient,status,dsn,relay,timestamp)
      VALUES(?,?,?,?,?,?)},
    undef,'HEALTH001','recipient@example.test','sent','2.0.0','local',$now
);

$s->set_state('/var/log/mail.log',12345,67890,$now_with_zone);

my $h=$s->health_status(quick_check=>1);

is($h->{quick_check},'ok','SQLite quick_check is healthy');
is($h->{status},'ok','single synthetic unknown message does not trigger warning threshold');
is($h->{counts}{messages},1,'health counts messages');
is($h->{counts}{events},1,'health counts events');
is($h->{counts}{recipients},1,'health counts recipients');
is($h->{recent_24h}{messages},1,'health reports recent messages');
is($h->{recent_24h}{unknown},1,'health reports recent unclassified messages');
is($h->{recent_24h}{unknown_pct},100,'health calculates unknown percentage');
is(scalar @{$h->{collectors}},1,'health exposes collector states');
is($h->{collectors}[0]{status},'active','fresh collector state with +HHMM timezone is active');
is($h->{collectors}[0]{updated_at},$now_with_zone,'collector preserves +HHMM timezone timestamp');
is($h->{collectors}[0]{offset},67890,'collector offset is preserved numerically');
is(scalar @{$h->{source_activity}},1,'health exposes event source activity');
is($h->{source_activity}[0]{source},'postfix','source activity identifies parser source');
is($h->{source_activity}[0]{events_24h},1,'source activity counts recent events');
ok($h->{db_size_bytes}>0,'health reports database size');
is($h->{last_message},$now,'health reports latest message timestamp');
is($h->{last_event},$now,'health reports latest event timestamp');

my $old_epoch=time-90001;
my $old_with_zone=strftime('%Y-%m-%dT%H:%M:%S%z',localtime($old_epoch));
$s->set_state('/var/log/old.log',999,111,$old_with_zone);

my $stale=$s->health_status();
is($stale->{stale_collectors},1,'collector older than 24 hours is counted as stale');
is(
    (grep { $_->{source} eq '/var/log/old.log' } @{$stale->{collectors}})[0]{status},
    'stale',
    'collector older than 24 hours has stale status'
);
is($stale->{status},'warning','stale collector raises overall health to warning');

my $ro=SendmailAnalyzer::Storage::SQLite->new(file=>$db,readonly=>1);
my $rh=$ro->health_status();
is($rh->{quick_check},'not_run','quick_check is opt-in for lightweight health requests');
is($rh->{counts}{messages},1,'health works through read-only storage connection');

done_testing;
