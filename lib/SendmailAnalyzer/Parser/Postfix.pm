package SendmailAnalyzer::Parser::Postfix;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;

sub _ev { my ($common,%x)=@_; return SendmailAnalyzer::Event->new(%$common,%x); }

sub parse {
    my ($class, $raw, %opt) = @_;
    my ($line,$common) = $class->event_common($raw,%opt);
    return if $line !~ /^postfix\/(\S+)\[\d+\]:\s+(.*)$/;
    my ($component,$msg)=($1,$2);

    if ($msg =~ /^([A-Za-z0-9]+):\s+message-id=<([^>]*)>/) {
        return _ev($common, source=>'postfix',type=>'message_id',component=>$component,queue_id=>$1,message_id=>$2);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+resent-message-id=<([^>]*)>/) {
        return _ev($common, source=>'postfix',type=>'message_id_alias',component=>$component,queue_id=>$1,message_id=>$2,alias_kind=>'resent-message-id');
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+from=<([^>]*)>,\s+size=(\d+),\s+nrcpt=(\d+)/) {
        return _ev($common, source=>'postfix',type=>'envelope',component=>$component,queue_id=>$1,sender=>$2,size=>0+$3,nrcpt=>0+$4);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+client=([^,\s]+)(.*)$/) {
        my ($qid,$relay,$tail)=($1,$2,$3);
        my ($host,$ip,$port)=$class->parse_relay($relay);
        my ($method)=$tail =~ /\bsasl_method=([^,\s]+)/;
        my ($user)=$tail =~ /\bsasl_username=([^,\s]+)/;
        return _ev($common, source=>'postfix',type=>'client',component=>$component,queue_id=>$qid,relay=>$relay,relay_host=>$host,relay_ip=>$ip,relay_port=>$port,sasl_method=>$method,sasl_username=>$user);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+to=<([^>]*)>,\s+(?:orig_to=<([^>]*)>,\s+)?relay=([^,]+),.*?\bdsn=([^,\s]+),\s+status=(\w+)\s*(?:\((.*)\))?/) {
        return _ev($common, source=>'postfix',type=>'delivery',component=>$component,queue_id=>$1,recipient=>$2,orig_recipient=>$3,relay=>$4,dsn=>$5,status=>lc($6),detail=>$7);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+passing\s+<([^>]*)>\s+to\s+transport=([^\s]+)/) {
        return _ev($common, source=>'postfix',type=>'transport_handoff',component=>$component,queue_id=>$1,recipient=>$2,transport=>$3);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+milter-reject:\s+([^:]+):\s+([245]\.[0-9]\.[0-9])\s+([^;]+);(.*)$/) {
        my ($qid,$stage,$dsn,$reason,$tail)=($1,$2,$3,$4,$5);
        my ($sender)=$tail =~ /\bfrom=<([^>]*)>/; my ($recipient)=$tail =~ /\bto=<([^>]*)>/;
        return _ev($common, source=>'postfix',type=>'milter_reject',component=>$component,queue_id=>$qid,stage=>$stage,dsn=>$dsn,reason=>$reason,sender=>$sender,recipient=>$recipient);
    }
    if ($msg =~ /^NOQUEUE:\s+milter-reject:\s+(\S+)\s+from\s+([^:]+):\s+(\d{3})\s+([245]\.[0-9]\.[0-9])\s+([^;]+);(.*)$/) {
        my ($stage,$peer,$code,$dsn,$reason,$tail)=($1,$2,$3,$4,$5,$6);
        my ($host,$ip,$port)=$class->parse_relay($peer);
        my ($sender)=$tail =~ /\bfrom=<([^>]*)>/; my ($recipient)=$tail =~ /\bto=<([^>]*)>/;
        my ($proto)=$tail =~ /\bproto=(\S+)/; my ($helo)=$tail =~ /\bhelo=<([^>]*)>/;
        return _ev($common, source=>'postfix',type=>'milter_reject',component=>$component,stage=>$stage,smtp_code=>0+$code,dsn=>$dsn,reason=>$reason,peer=>$peer,peer_host=>$host,peer_ip=>$ip,peer_port=>$port,sender=>$sender,recipient=>$recipient,proto=>$proto,helo=>$helo);
    }
    if ($msg =~ /^NOQUEUE:\s+reject:\s+([^:]+):\s+(\d{3})\s+([245]\.[0-9]\.[0-9])\s+([^;]+);\s+from=<([^>]*)>\s+to=<([^>]*)>\s+proto=(\S+)\s+helo=<([^>]*)>/) {
        return _ev($common, source=>'postfix',type=>'smtp_reject',component=>$component,stage=>$1,smtp_code=>0+$2,dsn=>$3,reason=>$4,sender=>$5,recipient=>$6,proto=>$7,helo=>$8);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+removed(?:\s+\(([^)]*)\)|\s+(.+))?\s*$/) {
        return _ev($common, source=>'postfix',type=>'removed',component=>$component,queue_id=>$1,detail=>defined($2)?$2:$3);
    }
    if ($msg =~ /^(Anonymous|Trusted|Untrusted) TLS connection established (to|from) (.+?):\s+(TLSv[^\s]+) with cipher ([^\s]+) \(([^)]+)\)(.*)$/) {
        my ($trust,$way,$peer,$proto,$cipher,$bits,$tail)=($1,$2,$3,$4,$5,$6,$7);
        my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'tls',component=>$component,direction=>($way eq 'to' ? 'outbound':'inbound'),trust=>lc($trust),peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,protocol=>$proto,cipher=>$cipher,bits=>$bits,detail=>$tail);
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+sasl_method=([^,\s]+),\s+sasl_username=([^,\s]+)/) {
        return _ev($common, source=>'postfix',type=>'smtp_auth',component=>$component,queue_id=>$1,success=>1,method=>$2,username=>$3);
    }
    if ($msg =~ /^warning:\s+([^:]+):\s+SASL\s+([^\s]+) authentication failed:\s*(.*)$/i) {
        my ($peer,$method,$detail)=($1,$2,$3); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'smtp_auth',component=>$component,success=>0,method=>$method,peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,detail=>$detail);
    }
    if ($msg =~ /^NOQUEUE:\s+(lost connection|timeout) after AUTH from ([^\s]+).*$/i) {
        my ($kind,$peer)=($1,$2); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'smtp_auth',component=>$component,success=>0,peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,detail=>lc($kind).' after AUTH');
    }
    if ($msg =~ /^SSL_accept error from ([^:]+):\s*(.*)$/i) {
        my ($peer,$detail)=($1,$2); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'tls_error',component=>$component,direction=>'inbound',peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,detail=>$detail);
    }
    if ($msg =~ /^warning:\s+TLS SNI from ([^\s]+) is invalid:\s*(.*)$/i) {
        my ($peer,$detail)=($1,$2); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'tls_error',component=>$component,direction=>'inbound',peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,detail=>'invalid SNI: '.$detail);
    }
    if ($msg =~ /^warning:\s+TLS library problem:\s*(.*)$/i) {
        return _ev($common, source=>'postfix',type=>'tls_error',component=>$component,direction=>'inbound',detail=>$1);
    }
    if ($msg =~ /^warning:\s+hostname\s+([^\s]+)\s+does not resolve to address\s+([^:\s]+)(?::\s*(.*))?$/i) {
        return _ev($common, source=>'postfix',type=>'peer_warning',component=>$component,peer_host=>$1,peer_ip=>$2,detail=>$3);
    }
    if ($msg =~ /^warning:\s+Connection rate limit exceeded:\s+(\d+)\s+from\s+([^\s]+)\s+for service\s+(\S+)/i) {
        my ($rate,$peer,$service)=($1,$2,$3); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'rate_limit',component=>$component,rate=>0+$rate,peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,service=>$service);
    }
    if ($msg =~ /^warning:\s+connect to Milter service\s+(.+):(\d+):\s*(.*)$/i) {
        return _ev($common, source=>'postfix',type=>'milter_error',component=>$component,milter_endpoint=>$1,milter_port=>0+$2,detail=>$3);
    }
    if ($component eq 'tlsproxy' && $msg =~ /^TLS handshake failed for service=(\S+) peer=\[([^\]]+)\]:(\d+)/i) {
        return _ev($common, source=>'postfix',type=>'tls_error',component=>$component,direction=>'inbound',service=>$1,peer_ip=>$2,peer_port=>0+$3,detail=>'TLS handshake failed');
    }
    if ($component eq 'tlsproxy' && $msg =~ /^(CONNECT from|DISCONNECT) \[([^\]]+)\]:(\d+)/i) {
        my ($act,$ip,$port)=($1,$2,$3); $act=lc($act); $act =~ s/ from//;
        return _ev($common, source=>'postfix',type=>'connection',component=>$component,action=>$act,peer_ip=>$ip,peer_port=>0+$port,peer=>"[$ip]:$port");
    }
    if ($msg =~ /^([A-Za-z0-9]+):\s+host\s+([^\s]+)\s+said:\s+(\d{3})[- ]([245]\.[0-9]\.[0-9]+)\s+(.*)$/i) {
        return _ev($common, source=>'postfix',type=>'remote_reply',component=>$component,queue_id=>$1,remote_host=>$2,smtp_code=>0+$3,dsn=>$4,detail=>$5);
    }
    if ($msg =~ /^(connect|disconnect) from ([^\s]+)(.*)$/) {
        my ($act,$peer,$detail)=($1,$2,$3); my ($h,$ip,$port)=$class->parse_relay($peer);
        return _ev($common, source=>'postfix',type=>'connection',component=>$component,action=>$act,peer=>$peer,peer_host=>$h,peer_ip=>$ip,peer_port=>$port,detail=>$detail);
    }
    return;
}
1;
