use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/../lib";
use SendmailAnalyzer::Parser; use SendmailAnalyzer::Classifier;

my $line='2026-09-15 01:00:06 #3001(rspamd_proxy) <abc123>; proxy; rspamd_task_write_log: id: <20260101010000.TEST0000002@relay.example.test>, qid: <B2C3D4E5F6A>, ip: 198.51.100.194, from: <monitor@relay.example.test>, (default: T (no action): [-53.30/16.00] [TEST_HAM(-50.00){},DMARC_POLICY_ALLOW(-0.50){relay.example.test;quarantine;},FORCE_ACTION_TEST_NOACTION(0.00){no action;}]), len: 342465, time: 256.862ms, dns req: 6, digest: <0123456789abcdef0123456789abcdef>, rcpts: <user@example.test>, mime_rcpts: <monitor@relay.example.test>, forced: no action "test fixture"; score=nan (set by force_actions), settings_id: TEST_PROFILE';
my $e=SendmailAnalyzer::Parser->parse_line($line,host=>'mailhost');
ok($e,'native rspamd task parsed'); my $h=$e->as_hash;
is($h->{source},'rspamd','source'); is($h->{type},'verdict','type'); is($h->{queue_id},'B2C3D4E5F6A','qid');
is($h->{message_id},'20260101010000.TEST0000002@relay.example.test','mid'); is($h->{action},'no action','action'); is($h->{score},-53.30,'score'); is($h->{required_score},16,'required');
is($h->{sender},'monitor@relay.example.test','sender'); is_deeply($h->{recipients},['user@example.test'],'rcpts');
is($h->{settings_id},'TEST_PROFILE','settings'); like($h->{forced_action},qr/^no action/,'forced action'); is($h->{dns_requests},6,'dns'); cmp_ok(abs($h->{scan_time_ms}-256.862),'<',0.001,'time ms');
is($h->{digest},'0123456789abcdef0123456789abcdef','digest'); is($h->{host},'mailhost','host supplied by collector');
ok(ref($h->{symbols}) eq 'ARRAY' && @{$h->{symbols}}==3,'symbols parsed'); is($h->{symbols}[0]{name},'TEST_HAM','symbol name'); is($h->{symbols}[1]{params},'relay.example.test;quarantine;','symbol params preserve semicolon');

my $rej='2026-09-15 15:53:23 #3002(normal) <def456>; task; rspamd_task_write_log: id: <test-policy@example.test>, from: <sender@example.net>, (default: T (reject): [4.40/16.00] [TEST_DOMAIN_BLOCK(0.00){blocked.example;},FORCE_ACTION_TEST_REJECT(0.00){reject;}]), len: 208, time: 205.933ms, dns req: 3, digest: <fedcba9876543210fedcba9876543210>, rcpts: <user@example.test>, mime_rcpts: <user@example.test>, file: stdin, forced: reject "5.7.1 Message rejected"; score=nan (set by force_actions)';
my $r=SendmailAnalyzer::Parser->parse_line($rej); ok($r,'qid-less rspamd test parsed'); my $rh=$r->as_hash; ok(!defined($rh->{queue_id}),'qid absent retained'); is($rh->{action},'reject','forced reject'); is($rh->{file},'stdin','file field');

my $c=SendmailAnalyzer::Classifier->new(local_domains=>['example.test']); my $qid=$c->add_event($e); is($qid,'B2C3D4E5F6A','native event correlates directly by qid'); my $m=$c->message_for($qid); is($m->{rspamd}{settings_id},'TEST_PROFILE','rich rspamd settings retained'); is($m->{rspamd}{action},'no action','rich action retained');
done_testing;
