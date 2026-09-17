use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Classifier;

my $c=SendmailAnalyzer::Classifier->new(local_domains=>['example.net']);
my $ok=eval {
    my $qid=$c->add_event({
        timestamp=>'2026-09-16T00:00:00', host=>'mailhost', source=>'postfix',
        type=>'envelope', queue_id=>'HASHREF01', sender=>'a@example.net', size=>123, nrcpt=>1,
    });
    die 'wrong qid' if !defined($qid) || $qid ne 'HASHREF01';
    my $m=$c->message_for('HASHREF01');
    die 'message missing' if !$m || ($m->{sender}||'') ne 'a@example.net';
    1;
};
ok($ok,'Classifier accepts an unblessed event hashref') or diag($@||'unknown error');

for my $rel (qw(lib/SendmailAnalyzer/Storage/SQLite.pm lib/SendmailAnalyzer/Classifier.pm lib/SendmailAnalyzer/Coverage.pm)) {
    open my $fh,'<',"$Bin/../$rel" or die $!; local $/; my $src=<$fh>; close $fh;
    like($src,qr/Scalar::Util\s+qw\(blessed\)/,"$rel imports blessed");
    unlike($src,qr/ref\([^\n]*\)\s*&&[^\n]*->can\(['\"]as_hash['\"]\)/,"$rel does not call can() on arbitrary references");
}

open my $sf,'<',"$Bin/../bin/sa10_selftest" or die $!; local $/; my $st=<$sf>; close $sf;
like($st,qr/sqlite v8 runtime detail:/,'selftest reports SQLite smoke exception detail');
done_testing;
