use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib"; use SendmailAnalyzer::Classifier; use SendmailAnalyzer::Event;
sub classify { my($from,$to)=@_; my $c=SendmailAnalyzer::Classifier->new(local_domains=>['example.test']); $c->add_event(SendmailAnalyzer::Event->new(source=>'postfix',type=>'envelope',queue_id=>'Q1',sender=>$from)); $c->add_event(SendmailAnalyzer::Event->new(source=>'postfix',type=>'delivery',queue_id=>'Q1',recipient=>$to,status=>'sent')); return $c->finalize->{Q1}{direction}; }
is(classify('outside@example.org','user@example.test'),'inbound','inbound');
is(classify('user@example.test','outside@example.org'),'outbound','outbound');
is(classify('a@example.test','b@example.test'),'internal','internal');
is(classify('a@example.org','b@example.net'),'relay','relay');
done_testing;
