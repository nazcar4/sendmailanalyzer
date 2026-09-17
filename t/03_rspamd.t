use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Parser::Rspamd;

my $line = 'Sep 14 04:49:55 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: milter-header-add: header X-Rspamd-Action: no action from mx.example.net[198.51.100.23]; from=<scanner@example.net> to=<user@example.test> proto=ESMTP helo=<mx.example.net>';
my $e = SendmailAnalyzer::Parser::Rspamd->parse($line);
is($e->{type}, 'verdict', 'Rspamd verdict event');
is($e->{queue_id}, 'A1B2C3D4E5F', 'Rspamd queue id');
is($e->{action}, 'no action', 'Rspamd action');

$line = 'Sep 14 04:49:55 mailhost postfix/cleanup[1001]: A1B2C3D4E5F: milter-header-add: header X-Spamd-Result: default: False [-2.29 / 16.00] [BAYES_HAM(-3.00)] from mx.example.net[198.51.100.23]; from=<scanner@example.net> to=<user@example.test> proto=ESMTP helo=<mx.example.net>';
$e = SendmailAnalyzer::Parser::Rspamd->parse($line);
is($e->{type}, 'score', 'Rspamd score event');
is($e->{score}, -2.29, 'Rspamd score');
is($e->{required_score}, 16, 'Rspamd required score from X-Spamd-Result');

done_testing;
