use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite; use SendmailAnalyzer::Event; use SendmailAnalyzer::Classifier;

if (!eval { require DBI; require DBD::SQLite; 1 }) { plan skip_all=>'DBI/SQLite unavailable'; }
my $db="/tmp/sa10-alias-$$.sqlite";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);
my $qid='ABCDEF12345'; my $alias='alias.123@example'; my $orig='original@example';
my $a=SendmailAnalyzer::Event->new(timestamp=>'2026-09-16T02:00:00',host=>'mailhost',source=>'postfix',type=>'message_id_alias',queue_id=>$qid,message_id=>$alias,alias_kind=>'resent-message-id',raw=>'alias');
$s->store_event($a);
is($s->resolve_message_id($alias),$qid,'persistent alias resolves to Queue-ID');
my ($kind)=$s->dbh->selectrow_array('SELECT kind FROM message_ids WHERE message_id=? AND queue_id=?',undef,$alias,$qid);
is($kind,'resent-message-id','alias kind persisted');

my $c=SendmailAnalyzer::Classifier->new(resolve_message_id=>sub{$s->resolve_message_id($_[0])},load_message=>sub{$s->load_classifier_message($_[0])});
$c->add_event($a);
my $scan=SendmailAnalyzer::Event->new(timestamp=>'2026-09-16T02:00:01',host=>'mailhost',source=>'spamassassin',type=>'scan_start',message_id=>$alias,original_message_id=>$orig,user=>'testuser',uid=>112,raw=>'scan');
$s->store_event($scan);
my $rq=$c->add_event($scan);
is($rq,$qid,'spamd aka alias resolves through classifier');
is($s->resolve_message_id($orig),$qid,'original Message-ID persisted as evidence alias');

my ($schema)=$s->dbh->selectrow_array("SELECT value FROM meta WHERE key='schema_version'");
is($schema,'8','schema v8');
unlink $db; unlink "$db-wal"; unlink "$db-shm";
done_testing;
