use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib"; use SendmailAnalyzer::Coverage;
my $c=SendmailAnalyzer::Coverage->new;
$c->add_line('Sep 16 10:00:01 mailhost postfix/qmgr[123]: ABC123: from=<a@example.com>, size=1000, nrcpt=1 (queue active)',year=>2026);
$c->add_line('Sep 16 10:00:02 mailhost postfix/anvil[1]: statistics: max connection rate 1/60s for (smtp:192.0.2.44) at Sep 16 10:00:00',year=>2026);
$c->add_line('Sep 16 10:00:03 mailhost weird-daemon[1]: some unsupported format',year=>2026);
my $r=$c->report; is($r->{total},3,'three lines'); is($r->{parsed},1,'one parsed'); is($r->{ignored},1,'one known noise'); is($r->{unknown},1,'one unknown');
done_testing;
