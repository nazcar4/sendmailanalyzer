use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Parser::Postscreen;

my $e = SendmailAnalyzer::Parser::Postscreen->parse('Sep 14 17:58:18 mailhost postfix/smtp/postscreen[2002]: DNSBL rank 2 for [203.0.113.227]:36227');
is($e->{type}, 'dnsbl_rank', 'DNSBL rank event');
is($e->{rank}, 2, 'rank parsed');
is($e->{client_ip}, '203.0.113.227', 'client IP');

$e = SendmailAnalyzer::Parser::Postscreen->parse('Sep 14 18:42:58 mailhost postfix/smtp/postscreen[2003]: NOQUEUE: reject: RCPT from [203.0.113.74]:37374: 550 5.7.1 Service unavailable; client [203.0.113.74] blocked using mail.abusix.zone; from=<sender@example.org>, to=<user@example.test>, proto=ESMTP, helo=<[192.0.2.4]>');
is($e->{type}, 'dnsbl_reject', 'DNSBL reject event');
is($e->{client_ip}, '203.0.113.74', 'reject IP');
is($e->{dnsbl}, 'mail.abusix.zone', 'DNSBL provider');
is($e->{sender}, 'sender@example.org', 'sender');
is($e->{recipient}, 'user@example.test', 'recipient');

done_testing;
