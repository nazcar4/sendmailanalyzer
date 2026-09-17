package SendmailAnalyzer::Parser::Rspamd;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($c,%x)=@_; SendmailAnalyzer::Event->new(%$c,%x) }
sub _num { my ($v)=@_; return undef if !defined($v) || $v !~ /^-?\d+(?:\.\d+)?$/; return 0+$v; }
sub _split_addr_list {
    my ($v)=@_; return [] if !defined($v) || $v eq '';
    return [ grep { length } map { my $x=$_; $x =~ s/^\s+|\s+$//g; $x } split /,/, $v ];
}
sub _parse_symbols {
    my ($txt)=@_; my @parts; my $cur=''; my $depth=0;
    for my $ch (split //,$txt||'') {
        if ($ch eq '{') { $depth++; $cur.=$ch; next; }
        if ($ch eq '}') { $depth-- if $depth>0; $cur.=$ch; next; }
        if ($ch eq ',' && $depth==0) { push @parts,$cur if length $cur; $cur=''; next; }
        $cur.=$ch;
    }
    push @parts,$cur if length $cur;
    my @out;
    for my $p (@parts) {
        $p =~ s/^\s+|\s+$//g; next if $p eq '';
        if ($p =~ /^([A-Za-z0-9_]+)\((-?\d+(?:\.\d+)?)\)(?:\{(.*)\})?$/s) {
            push @out,{name=>$1,score=>0+$2,params=>defined($3)?$3:''};
        } else { push @out,{raw=>$p}; }
    }
    return \@out;
}
sub parse {
    my ($class,$raw,%opt)=@_;

    # Native Rspamd file log (logging.type=file). This is the richest source:
    # Queue-ID/Message-ID, score, symbols, forced action, settings and timings.
    if ($raw =~ /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+#(\d+)\(([^)]+)\)\s+<([^>]+)>;\s*([^;]+);\s*rspamd_task_write_log:\s*(.*)$/s) {
        my ($date,$clock,$pid,$worker,$task_id,$module,$body)=($1,$2,$3,$4,$5,$6,$7);
        chomp $body;
        my ($mid)=$body =~ /^id:\s*<([^>]*)>/;
        my ($qid)=$body =~ /(?:^|,\s*)qid:\s*<([^>]*)>/;
        my ($ip)=$body =~ /(?:^|,\s*)ip:\s*([^,]+)(?:,|$)/;
        my ($user)=$body =~ /(?:^|,\s*)user:\s*([^,]+)(?:,|$)/;
        my ($sender)=$body =~ /(?:^|,\s*)from:\s*<([^>]*)>/;
        my ($flag,$action,$score,$required,$symbols,$len,$elapsed,$dns,$digest,$tail)=
            $body =~ /\(default:\s*([TF])\s+\(([^)]+)\):\s*\[([^\/\]]+)\/([^\]]+)\]\s*\[(.*)\]\),\s*len:\s*(\d+),\s*time:\s*([^,]+),\s*dns req:\s*(\d+),\s*digest:\s*<([^>]*)>(.*)$/s;
        return if !defined $action;
        my ($rcpts)=$tail =~ /,\s*rcpts:\s*<([^>]*)>/;
        my ($mime_rcpts)=$tail =~ /,\s*mime_rcpts:\s*<([^>]*)>/;
        my ($file)=$tail =~ /,\s*file:\s*([^,]+?)(?=,\s*(?:forced|settings_id):|$)/;
        my ($forced)=$tail =~ /,\s*forced:\s*(.*?)(?=,\s*settings_id:|$)/s;
        my ($settings_id)=$tail =~ /,\s*settings_id:\s*([^,\s]+)/;
        my $elapsed_ms;
        if (defined $elapsed && $elapsed =~ /^(-?\d+(?:\.\d+)?)ms$/) { $elapsed_ms=0+$1; }
        elsif (defined $elapsed && $elapsed =~ /^(-?\d+(?:\.\d+)?)s$/) { $elapsed_ms=(0+$1)*1000; }
        my $common={timestamp=>"${date}T${clock}",host=>($opt{host}||undef),raw=>$raw};
        return _ev($common,
            source=>'rspamd',type=>'verdict',queue_id=>$qid,message_id=>$mid,
            action=>lc($action),score=>_num($score),required_score=>_num($required),
            rspamd_is_spam=>($flag eq 'T'?1:0),client_ip=>$ip,user=>$user,sender=>$sender,
            symbols=>_parse_symbols($symbols),recipients=>_split_addr_list($rcpts),mime_recipients=>_split_addr_list($mime_rcpts),
            length=>0+$len,scan_time_ms=>$elapsed_ms,dns_requests=>0+$dns,digest=>$digest,
            forced_action=>$forced,settings_id=>$settings_id,file=>$file,
            rspamd_worker=>$worker,rspamd_pid=>0+$pid,rspamd_task_id=>$task_id,rspamd_module=>$module,
            evidence=>'rspamd.log');
    }

    # Keep operationally relevant native Rspamd warnings without treating all
    # daemon startup/debug lines as mail-flow events.
    if ($raw =~ /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+#(\d+)\(([^)]+)\)(?:\s+<([^>]+)>;\s*([^;]+);)?\s*(?:([^:]+):\s*)?(.*)$/s) {
        my ($date,$clock,$pid,$worker,$task_id,$module,$function,$detail)=($1,$2,$3,$4,$5,$6,$7,$8);
        if (($detail||'') =~ /\b(?:SECURITY:|failed|error|timed out|timeout)\b/i && ($detail||'') !~ /cannot find content-type for a message/i) {
            my $common={timestamp=>"${date}T${clock}",host=>($opt{host}||undef),raw=>$raw};
            return _ev($common,source=>'rspamd',type=>'daemon_warning',detail=>$detail,rspamd_worker=>$worker,rspamd_pid=>0+$pid,rspamd_task_id=>$task_id,rspamd_module=>$module,rspamd_function=>$function,evidence=>'rspamd.log');
        }
    }

    my ($line,$common)=$class->event_common($raw,%opt);
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Rspamd-Action:\s*([^\s].*?)\s+from\s+/) {
        my ($qid,$a)=($1,$2); $a =~ s/\s+$//;
        return _ev($common,source=>'rspamd',type=>'verdict',queue_id=>$qid,action=>lc($a),evidence=>'X-Rspamd-Action');
    }
    # X-Spam-Status is emitted by both SpamAssassin and some Rspamd milter
    # configurations.  A configured HEADER_ROUTE is authoritative.  Without a
    # route, a compact status that lacks SpamAssassin's required/tests fields is
    # treated as Rspamd; the detailed form is left to the SpamAssassin parser.
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Spam-Status:\s*(Yes|No),\s*score=(-?\d+(?:\.\d+)?)(.*?)\s+from\s+/i) {
        my ($qid,$yn,$score,$middle)=($1,$2,$3,$4);
        my $route=$opt{header_route_engine};
        my $looks_sa=($middle =~ /\b(?:required|tests)=/i) ? 1 : 0;
        if ((defined($route) && $route eq 'rspamd') || (!defined($route) && !$looks_sa)) {
            return _ev($common,source=>'rspamd',type=>'score',queue_id=>$qid,detected=>(lc($yn) eq 'yes'?1:0),score=>0+$score,evidence=>'X-Spam-Status');
        }
    }

    # Unambiguous Rspamd standard extended headers.
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Spamd-Result:\s*.*?\[\s*(-?\d+(?:\.\d+)?)\s*\/\s*(-?\d+(?:\.\d+)?)\s*\]/i) {
        my ($qid,$score,$required)=($1,$2,$3);
        return _ev($common,source=>'rspamd',type=>'score',queue_id=>$qid,score=>0+$score,required_score=>0+$required,evidence=>'X-Spamd-Result');
    }
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Rspamd-Score:\s*([^\s]+)/) {
        my ($score)=$2 =~ /(-?\d+(?:\.\d+)?)/;
        return _ev($common,source=>'rspamd',type=>'score',queue_id=>$1,score=>defined $score?0+$score:undef,evidence=>'X-Rspamd-Score');
    }
    if ($line =~ /^rspamd(?:_proxy)?\[\d+\]:.*?\((reject|add header|rewrite subject|greylist|no action|soft reject)\):\s*\[(-?\d+(?:\.\d+)?)\s*\/\s*(-?\d+(?:\.\d+)?)\]/i) {
        return _ev($common,source=>'rspamd',type=>'verdict',action=>lc($1),score=>0+$2,required_score=>0+$3,evidence=>'syslog');
    }
    return;
}
1;
