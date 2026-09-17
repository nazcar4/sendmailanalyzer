package SendmailAnalyzer::Parser::OpenDMARC;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($c,%x)=@_; SendmailAnalyzer::Event->new(%$c,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);
    return if $line !~ /^opendmarc\[\d+\]:\s+(.*)$/;
    my $msg=$1;
    if ($msg =~ /^([A-Za-z0-9]+):\s+([^\s]+)\s+(none|pass|fail|reject|quarantine)\s*$/i) { return _ev($common,source=>'opendmarc',type=>'dmarc_result',queue_id=>$1,domain=>$2,result=>lc($3)); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+spf=([^\s]+).*?dkim=([^\s]+).*?dmarc=([^\s]+)/i) { return _ev($common,source=>'opendmarc',type=>'authentication_results',queue_id=>$1,spf=>lc($2),dkim=>lc($3),dmarc=>lc($4)); }
    return;
}
1;
