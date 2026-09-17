use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Parser::Postfix;

my $e = SendmailAnalyzer::Parser::Postfix->parse('Sep 14 04:49:53 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: message-id=<20260101000000.TEST0000001@mx.example.net>');
is($e->{type}, 'message_id', 'message-id event');
is($e->{queue_id}, 'A1B2C3D4E5F', 'queue id parsed');
is($e->{message_id}, '20260101000000.TEST0000001@mx.example.net', 'message id parsed');

$e = SendmailAnalyzer::Parser::Postfix->parse('Sep 14 04:49:55 mailhost postfix/lmtp[1004]: A1B2C3D4E5F: to=<user@example.test>, relay=mail.example.test[private/dovecot-lmtp], delay=2.1, delays=2/0/0/0.03, tls=none, dsn=2.0.0, status=sent (250 2.0.0 Saved)');
is($e->{type}, 'delivery', 'delivery event');
is($e->{status}, 'sent', 'delivery status');
is($e->{recipient}, 'user@example.test', 'recipient parsed');

done_testing;
