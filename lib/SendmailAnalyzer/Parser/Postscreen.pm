package SendmailAnalyzer::Parser::Postscreen;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($common,%x)=@_; SendmailAnalyzer::Event->new(%$common,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);
    if ($line =~ /^postfix\/dnsblog\[\d+\]:\s+addr\s+([^\s]+)\s+listed by domain\s+([^\s]+)\s+as\s+([^\s]+)/) {
        return _ev($common,source=>'postscreen',type=>'dnsbl_listing',client_ip=>$1,dnsbl=>$2,result_ip=>$3);
    }
    return if $line !~ /^postfix\/(?:smtp\/)?postscreen\[\d+\]:\s+(.*)$/;
    my $msg=$1;
    if ($msg =~ /^DNSBL rank\s+(-?\d+)\s+for\s+\[([^\]]+)\]:(\d+)/) {
        return _ev($common,source=>'postscreen',type=>'dnsbl_rank',rank=>0+$1,client_ip=>$2,client_port=>0+$3);
    }
    if ($msg =~ /^NOQUEUE:\s+reject:\s+RCPT from \[([^\]]+)\]:(\d+):\s+(\d{3})\s+([245]\.[0-9]\.[0-9])\s+([^;]+);\s+client \[[^\]]+\] blocked using ([^;]+);\s+from=<([^>]*)>,\s+to=<([^>]*)>/) {
        return _ev($common,source=>'postscreen',type=>'dnsbl_reject',client_ip=>$1,client_port=>0+$2,smtp_code=>0+$3,dsn=>$4,reason=>$5,dnsbl=>$6,sender=>$7,recipient=>$8);
    }
    if ($msg =~ /^(BARE NEWLINE|COMMAND TIME LIMIT|COMMAND COUNT LIMIT|NON-SMTP COMMAND|PREGREET)\s+from\s+\[([^\]]+)\]:(\d+)\s*(.*)$/i) {
        return _ev($common,source=>'postscreen',type=>'protocol_violation',action=>lc($1),client_ip=>$2,client_port=>0+$3,detail=>$4);
    }
    if ($msg =~ /^(PASS NEW|PASS OLD|CONNECT|DISCONNECT|PREGREET|HANGUP|WHITELISTED)\b\s*(.*)$/) {
        my ($action,$detail)=($1,$2); my ($ip,$port)=$detail =~ /\[([^\]]+)\]:(\d+)/;
        return _ev($common,source=>'postscreen',type=>'connection',action=>lc($action),detail=>$detail,client_ip=>$ip,client_port=>defined $port?0+$port:undef);
    }
    return;
}
1;
