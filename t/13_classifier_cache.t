use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use SendmailAnalyzer::Classifier; use SendmailAnalyzer::Event;

my $loaded=0;
my $c=SendmailAnalyzer::Classifier->new(
 local_domains=>['example.test'],
 load_message=>sub { my ($qid)=@_; $loaded++; return if $qid ne 'OLD123'; return {queue_id=>$qid,message_id=>'same@example',sender=>'root@example.test',recipients=>['outside@example.net'],delivery=>{sent=>1,bounced=>0,deferred=>0,expired=>0},spamassassin=>{},rspamd=>{},dkim=>{},dmarc=>{},antivirus=>{},classification=>{},auth=>{},tls=>[],events=>[]}; },
 resolve_message_id=>sub { $_[0] eq 'same@example' ? 'OLD123' : undef },
);
my $e=SendmailAnalyzer::Event->new(source=>'spamassassin',type=>'verdict',message_id=>'same@example',detected=>1,score=>6,timestamp=>'2026-09-16T01:00:00');
is($c->add_event($e),'OLD123','message-id resolves to persisted queue id');
ok($loaded>=1,'persisted message hydrated');
my $m=$c->message_for('OLD123');
is($m->{sender},'root@example.test','persisted sender preserved');
is($m->{direction},'outbound','direction survives collector restart via hydration');
ok($m->{classification}{spam_delivered},'late SA verdict + persisted delivery becomes spam_delivered');

for my $i (1..8) {
 my $q="Q$i"; $c->add_event(SendmailAnalyzer::Event->new(source=>'postfix',type=>'envelope',queue_id=>$q,sender=>'a@example.test',size=>1,nrcpt=>1,timestamp=>sprintf('2026-09-16T01:00:%02d',$i)));
}
my $before=scalar keys %{$c->messages}; ok($before>=9,'cache populated');
my $dropped=$c->prune_cache(4); ok($dropped>=5,'cache pruning drops old messages'); is(scalar(keys %{$c->messages}),4,'cache bounded to configured limit');
done_testing;
