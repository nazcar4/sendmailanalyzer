use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Parser;
use SendmailAnalyzer::Coverage;

sub p { SendmailAnalyzer::Parser->parse_line($_[0],year=>2026) }

my $e=p('Sep 16 02:00:01 mailhost dovecot: pop3-login: Login aborted: Inactivity (no auth attempts in 180 secs) (no_auth_attempts): user=<>, rip=203.0.113.2, lip=203.0.113.3, TLS, session=<abc>');
is($e->{source},'dovecot','no-auth login source'); is($e->{type},'login','no-auth login parsed'); ok(!$e->{success},'no-auth login is failure'); is($e->{remote_ip},'203.0.113.2','no-auth remote ip');

$e=p('Sep 16 02:00:02 mailhost postfix/tlsproxy[123]: TLS handshake failed for service=smtp peer=[203.0.113.4]:63991');
is($e->{type},'tls_error','tlsproxy handshake failure'); is($e->{service},'smtp','tlsproxy service'); is($e->{peer_ip},'203.0.113.4','tlsproxy peer ip');

$e=p('Sep 16 02:00:03 mailhost postfix/tlsproxy[123]: CONNECT from [203.0.113.5]:37374');
is($e->{type},'connection','tlsproxy connect'); is($e->{action},'connect','tlsproxy connect action');
$e=p('Sep 16 02:00:04 mailhost postfix/tlsproxy[123]: DISCONNECT [203.0.113.5]:37374');
is($e->{type},'connection','tlsproxy disconnect'); is($e->{action},'disconnect','tlsproxy disconnect action');

$e=p('Sep 16 02:00:05 mailhost postfix/smtpd[123]: warning: Connection rate limit exceeded: 44 from unknown[203.0.113.6] for service smtpd');
is($e->{type},'rate_limit','connection rate-limit parsed'); is($e->{rate},44,'rate-limit value'); is($e->{peer_ip},'203.0.113.6','rate-limit ip');

$e=p('Sep 16 02:00:06 mailhost postfix/smtpd[123]: warning: connect to Milter service inet:127.0.0.1:11332: Connection refused');
is($e->{type},'milter_error','milter connection error parsed'); is($e->{milter_endpoint},'inet:127.0.0.1','milter endpoint'); is($e->{milter_port},11332,'milter port');

$e=p('Sep 16 02:00:07 mailhost postfix/cleanup[123]: ABCDEF12345: resent-message-id=<SrLz1TitKNF.A.e7GP.z5CqqB@bendel>');
is($e->{type},'message_id_alias','resent Message-ID parsed'); is($e->{queue_id},'ABCDEF12345','resent Message-ID qid'); is($e->{alias_kind},'resent-message-id','resent Message-ID alias kind');

$e=p('Sep 16 02:00:08 mailhost spamd[123]: spamd: processing message <3DCDBAB3-AE63-453A-ACCF-X@example.org> aka <SrLz1TitKNF.A.e7GP.z5CqqB@bendel> for testuser:112');
is($e->{type},'scan_start','spamd aka scan parsed'); is($e->{message_id},'SrLz1TitKNF.A.e7GP.z5CqqB@bendel','spamd aka correlation id'); is($e->{original_message_id},'3DCDBAB3-AE63-453A-ACCF-X@example.org','spamd original id retained');

$e=p('Sep 16 02:00:09 mailhost opendkim[123]: ABCDEF12345: failed to parse authentication-results: header field');
is($e->{type},'dkim_metadata_error','OpenDKIM metadata error parsed'); is($e->{queue_id},'ABCDEF12345','OpenDKIM error qid');

$e=p('Sep 16 02:00:10 mailhost postfix/submission/smtpd[123]: warning: hostname static.vnpt.vn does not resolve to address 203.0.113.8');
is($e->{type},'peer_warning','hostname warning without suffix parsed'); is($e->{peer_ip},'203.0.113.8','hostname warning ip');

$e=p('Sep 16 02:00:11 mailhost postfix/smtp[123]: ABCDEF12345: host gmail-smtp-in.l.google.com[203.0.113.9] said: 421-4.7.28 Gmail has detected an unusual rate of mail originating from your SPF domain');
is($e->{type},'remote_reply','remote SMTP reply parsed'); is($e->{smtp_code},421,'remote SMTP code'); is($e->{dsn},'4.7.28','remote enhanced status');

$e=p('Sep 16 02:00:12 mailhost postfix/smtp/postscreen[123]: DISCONNECT [203.0.113.10]:58416');
is($e->{source},'postscreen','postscreen disconnect source'); is($e->{type},'connection','postscreen disconnect parsed'); is($e->{action},'disconnect','postscreen disconnect action');


$e=p('Sep 16 02:00:13 mailhost postfix/qmgr[123]: ABCDEF12345: removed 654321');
is($e->{type},'removed','qmgr removed with trailing detail parsed'); is($e->{detail},'654321','removed trailing detail preserved');

my $c=SendmailAnalyzer::Coverage->new;
$c->add_line('Sep 16 02:01:01 mailhost postfix/smtp/postscreen[123]: cache lmdb:/var/lib/postfix/postscreen_cache full cleanup: retained=220 dropped=15 entries',year=>2026);
$c->add_line('Sep 16 02:01:02 mailhost dovecot: pop3(testuser)<2005><session>: Disconnected: Inactivity - no input for 600 secs top=0/0, retr=0/0, del=0/0, size=1234',year=>2026);
my $r=$c->report;
is($r->{unknown},0,'parser bookkeeping patterns no longer unknown'); is($r->{ignored},2,'parser bookkeeping patterns explicitly ignored');

done_testing;
