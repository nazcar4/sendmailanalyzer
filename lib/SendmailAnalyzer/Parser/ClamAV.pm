package SendmailAnalyzer::Parser::ClamAV;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($c,%x)=@_; SendmailAnalyzer::Event->new(%$c,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);
    # Parse the standard ClamAV milter result header.  Local header rewrites
    # are deliberately ignored so the parser remains portable.
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Virus-Status:\s*(.*?)\s+from\s+/i) {
        my ($qid,$value)=($1,$2); $value =~ s/\s+$//;
        my $status=lc($value||'unknown');
        my $normalized=$status =~ /(?:infected|found|virus)/ ? 'virus' : $status =~ /^(?:clean|ok)\b/ ? 'clean' : $status;
        my ($virus)=$value =~ /(?:infected|found)\s*\(?([^)]*)\)?/i;
        $virus =~ s/^\s+|\s+$//g if defined $virus;
        return _ev($common,source=>'clamav',type=>'virus_verdict',queue_id=>$qid,status=>$status,normalized_status=>$normalized,virus=>$virus,evidence=>'X-Virus-Status');
    }
    if ($line =~ /^clamav-milter\[\d+\]:\s+(?:Message|Quarantined).*?([A-Za-z0-9._-]+)\s+FOUND/i) { return _ev($common,source=>'clamav',type=>'virus_verdict',status=>'infected',normalized_status=>'virus',virus=>$1); }
    if ($line =~ /^clamav-milter\[\d+\]:\s+(.*)$/) { return _ev($common,source=>'clamav',type=>'daemon_log',detail=>$1); }
    return;
}
1;
