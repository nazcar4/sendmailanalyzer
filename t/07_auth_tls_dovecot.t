use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib"; use SendmailAnalyzer::Parser;
my $e=SendmailAnalyzer::Parser->parse_line('Sep 16 10:00:01 mailhost postfix/smtpd[123]: ABC123: client=host.example[203.0.113.10], sasl_method=PLAIN, sasl_username=user@example.net',year=>2026);
is($e->{type},'client','client parsed'); is($e->{sasl_username},'user@example.net','SASL user'); is($e->{timestamp},'2026-09-16T10:00:01','timestamp');
$e=SendmailAnalyzer::Parser->parse_line('Sep 16 10:00:02 mailhost postfix/smtpd[123]: Anonymous TLS connection established from host.example[203.0.113.10]: TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits)',year=>2026);
is($e->{type},'tls','TLS parsed'); is($e->{direction},'inbound','TLS inbound'); is($e->{protocol},'TLSv1.3','TLS version');
$e=SendmailAnalyzer::Parser->parse_line('Sep 16 10:00:03 mailhost dovecot: imap-login: Login: user=<user@example.net>, method=PLAIN, rip=203.0.113.10, lip=192.0.2.10, mpid=123, TLS',year=>2026);
is($e->{type},'login','Dovecot login'); is($e->{user},'user@example.net','Dovecot user'); ok($e->{success},'Dovecot success');
done_testing;
