use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Parser;
use SendmailAnalyzer::Classifier;
use SendmailAnalyzer::Coverage;

my $e=SendmailAnalyzer::Parser->parse_line('Sep 15 19:45:11 mailhost postfix/smtp[123]: Untrusted TLS connection established to mx.example.net[198.51.100.23]:25: TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits) key-exchange x25519',year=>2026);
is($e->{type},'tls','outbound TLS with port parsed'); is($e->{direction},'outbound','outbound direction'); is($e->{peer_port},25,'peer port parsed');

$e=SendmailAnalyzer::Parser->parse_line('Sep 15 20:10:01 mailhost postfix/local[123]: A1B2C3D4E5F: passing <user@example.test> to transport=lmtp',year=>2026);
is($e->{type},'transport_handoff','local transport handoff'); is($e->{recipient},'user@example.test','handoff recipient'); is($e->{transport},'lmtp','handoff transport');

$e=SendmailAnalyzer::Parser->parse_line('Sep 15 20:10:02 mailhost postfix/dnsblog[123]: addr 203.0.113.9 listed by domain token.zen.dq.spamhaus.net as 127.0.0.2',year=>2026);
is($e->{source},'postscreen','dnsblog attributed to postscreen'); is($e->{type},'dnsbl_listing','dnsblog parsed'); is($e->{dnsbl},'token.zen.dq.spamhaus.net','dnsbl domain');

$e=SendmailAnalyzer::Parser->parse_line('Sep 15 20:10:03 mailhost postfix/submission/smtpd[123]: NOQUEUE: lost connection after AUTH from unknown[203.0.113.10]',year=>2026);
is($e->{type},'smtp_auth','lost AUTH connection parsed'); ok(!$e->{success},'AUTH failure'); is($e->{peer_ip},'203.0.113.10','AUTH peer ip');

$e=SendmailAnalyzer::Parser->parse_line('Sep 15 20:10:04 mailhost postfix/smtpd[123]: NOQUEUE: milter-reject: MAIL from blocked.example[192.0.2.53]: 451 4.7.1 Service unavailable - try again later; from=<bounce@example.net> proto=ESMTP helo=<blocked.example>',year=>2026);
is($e->{type},'milter_reject','NOQUEUE milter reject parsed'); is($e->{smtp_code},451,'milter reject smtp code'); is($e->{sender},'bounce@example.net','milter reject sender');

$e=SendmailAnalyzer::Parser->parse_line('Sep 14 04:49:55 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: milter-header-add: header X-Spam-Status: Yes, score=5.5 required=5.0 tests=DKIM_SIGNED,DKIM_VALID,SPF_PASS autolearn=no from mx.example.net[198.51.100.23]; from=<scanner@example.net> to=<user@example.test> proto=ESMTP helo=<mx.example.net>',year=>2026);
is($e->{source},'spamassassin','standard SA header source'); is($e->{type},'verdict','standard SA header verdict'); ok($e->{detected},'standard SA detected spam'); is($e->{queue_id},'A1B2C3D4E5F','standard SA correlated by qid'); cmp_ok($e->{score},'==',5.5,'standard SA score');

my $cl=SendmailAnalyzer::Classifier->new(local_domains=>['example.test']);
$cl->add_event(SendmailAnalyzer::Parser->parse_line('Sep 14 04:49:55 mailhost postfix/qmgr[1]: A1B2C3D4E5F: from=<scanner@example.net>, size=6000, nrcpt=1 (queue active)',year=>2026));
$cl->add_event(SendmailAnalyzer::Parser->parse_line('Sep 14 04:49:55 mailhost postfix/local[2]: A1B2C3D4E5F: passing <user@example.test> to transport=lmtp',year=>2026));
$cl->add_event($e);
$cl->add_event(SendmailAnalyzer::Parser->parse_line('Sep 14 04:49:56 mailhost postfix/lmtp[3]: A1B2C3D4E5F: to=<user@example.test>, relay=127.0.0.1[127.0.0.1]:24, delay=0.3, delays=0.1/0/0/0.2, dsn=2.0.0, status=sent (250 Saved)',year=>2026));
my $m=$cl->message_for('A1B2C3D4E5F'); ok($m->{classification}{spam_detected},'SA detection retained'); ok(!$m->{classification}{spam_rejected},'delivered SA-positive message not rejected'); ok($m->{classification}{spam_delivered},'delivered SA-positive classified correctly');

my $c=SendmailAnalyzer::Coverage->new;
for my $line (
 'Sep 15 20:11:01 mailhost opendkim[1500]: A1B2C3D4E5F: not authenticated',
 'Sep 15 20:11:02 mailhost opendkim[1500]: A1B2C3D4E5F: mx.example.net [198.51.100.23] not internal',
 'Sep 15 20:11:03 mailhost opendmarc[1496]: ignoring connection from localhost',
 'Sep 15 20:11:04 mailhost opendmarc[1496]: implicit authentication service: mail.example.test',
 'Sep 15 20:11:05 mailhost postfix/cleanup[1]: ABC12345678: milter-header-add: header X-Rspamd-Server: mail.example.test from localhost[127.0.0.1]; from=<root@example.test> to=<user@example.test>',
 'Sep 15 20:11:06 mailhost dovecot: lmtp(2004): Connect from local',
 'Sep 15 20:11:07 mailhost spamd[123]: spamd: server started on IO::Socket::IP [127.0.0.1]:783 (running version 4.0.1)'
) { $c->add_line($line,year=>2026); }
my $r=$c->report; is($r->{unknown},0,'synthetic metadata patterns are no longer unknown'); is($r->{ignored},7,'synthetic metadata intentionally ignored');

done_testing;
