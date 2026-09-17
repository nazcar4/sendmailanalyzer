use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Parser;
use SendmailAnalyzer::Coverage;

my $e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:01 mailhost dovecot: pop3-login: Logged in: user=<testuser>, method=PLAIN, rip=203.0.113.4, lip=203.0.113.5, mpid=2001, TLS, session=<abc>',year=>2026);
is($e->{source},'dovecot','POP3 logged-in source'); is($e->{type},'login','POP3 logged-in parsed'); ok($e->{success},'POP3 success'); is($e->{user},'testuser','POP3 user');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:02 mailhost dovecot: pop3-login: Login aborted: Inactivity (auth failed, 2 attempts in 178 secs) (auth_failed): user=<testuser>, method=PLAIN, rip=203.0.113.4, lip=203.0.113.5, TLS, session=<abc>',year=>2026);
is($e->{type},'login','POP3 failed login parsed'); ok(!$e->{success},'POP3 failed login status'); like($e->{detail},qr/auth failed/,'POP3 failure detail');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:03 mailhost postfix/lmtp[123]: ABCDEF12345: to=<user@example.test>, orig_to=<postmaster>, relay=mail.example.test[private/dovecot-lmtp], delay=0.09, delays=0.01/0.01/0.04/0.03, tls=none, dsn=2.0.0, status=sent (250 Saved)',year=>2026);
is($e->{type},'delivery','LMTP orig_to delivery'); is($e->{orig_recipient},'postmaster','orig_to preserved'); is($e->{status},'sent','LMTP sent');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:04 mailhost postfix/submission/smtpd[123]: SSL_accept error from unknown[203.0.113.9]: -1',year=>2026);
is($e->{type},'tls_error','SSL_accept error parsed'); is($e->{peer_ip},'203.0.113.9','SSL peer ip');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:05 mailhost postfix/smtps/smtpd[123]: warning: TLS SNI from unknown[203.0.113.10] is invalid: 203.0.113.10',year=>2026);
is($e->{type},'tls_error','invalid SNI parsed');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:06 mailhost postfix/submission/smtpd[123]: warning: TLS library problem: error:0A000102:SSL routines::unsupported protocol:../ssl/statem/statem_srvr.c:1780:',year=>2026);
is($e->{type},'tls_error','TLS library problem parsed');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:07 mailhost postfix/submission/smtpd[123]: warning: hostname host.example does not resolve to address 203.0.113.11: Name or service not known',year=>2026);
is($e->{type},'peer_warning','reverse/forward hostname warning parsed'); is($e->{peer_host},'host.example','warning hostname');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:08 mailhost opendkim[123]: ABCDEF12345: bad signature data',year=>2026);
is($e->{type},'dkim_verification','bad DKIM parsed'); is($e->{result},'fail','bad DKIM is failure');

$e=SendmailAnalyzer::Parser->parse_line('Sep 16 00:01:09 mailhost postfix/smtp/postscreen[123]: BARE NEWLINE from [203.0.113.12]:58416 after',year=>2026);
is($e->{type},'protocol_violation','postscreen bare newline parsed'); is($e->{client_ip},'203.0.113.12','bare newline ip');

my $c=SendmailAnalyzer::Coverage->new;
for my $line (
 'Sep 16 00:02:02 mailhost spamd[2]: spamd: server pid: 1321',
 'Sep 16 00:02:03 mailhost spamd[2]: spamd: server socket closed, type IO::Socket::IP',
 'Sep 16 00:02:04 mailhost spamd[2]: spamd: server hit by SIGHUP, restarting',
 'Sep 16 00:02:05 mailhost spamd[2]: spamd: handle_user (userdir) unable to find user: \'gps\'',
 'Sep 16 00:02:06 mailhost spamd[2]: pyzor: failure to parse response "0"',
 'Sep 16 00:02:07 mailhost spamd[2]: Did not receive a response from the pyzor server public.pyzor.org:24441 for 5 seconds!',
 'Sep 16 00:02:08 mailhost spamd[2]: async: aborting after 3.379 s, deadline shrunk: URIBL',
 'Sep 16 00:02:09 mailhost opendmarc[2]: ABCDEF12345 ignoring Authentication-Results at 14 from apache.org'
) { $c->add_line($line,year=>2026); }
my $r=$c->report; is($r->{unknown},0,'remaining operational patterns no longer unknown'); is($r->{ignored},8,'operational patterns explicitly ignored');

done_testing;
