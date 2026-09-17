use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Parser::SpamAssassin;

my $line = '2026-09-14T04:49:55.644789+02:00 mailhost spamd[1003]: spamd: result: Y  5 - DKIM_SIGNED,DKIM_VALID,SPF_PASS scantime=1.8,size=6353,user=testuser,uid=112,required_score=5.0,rhost=localhost,raddr=127.0.0.1,rport=50740,mid=<20260101000000.TEST0000001@mx.example.net>,autolearn=disabled';
my $e = SendmailAnalyzer::Parser::SpamAssassin->parse($line);
is($e->{type}, 'verdict', 'SA verdict event');
ok($e->{detected}, 'SA detected spam');
is($e->{score}, 5, 'SA score');
is($e->{required_score}, 5, 'required score');
is($e->{message_id}, '20260101000000.TEST0000001@mx.example.net', 'SA message-id');
is_deeply($e->{tests}, [qw(DKIM_SIGNED DKIM_VALID SPF_PASS)], 'SA symbols split');

done_testing;
