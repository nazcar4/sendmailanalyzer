package SendmailAnalyzer::Classifier;
use strict;
use warnings;
use Scalar::Util qw(blessed);

sub new {
    my ($class,%opt)=@_;
    my %ld=map { lc($_)=>1 } @{ $opt{local_domains} || [] };
    return bless {
        messages=>{}, mid_to_qid=>{}, pending_by_mid=>{},
        resolve_message_id=>$opt{resolve_message_id}, load_message=>$opt{load_message},
        local_domains=>\%ld,
    }, $class;
}
sub _blank_message {
    my ($qid)=@_;
    return {
        queue_id=>$qid, recipients=>[], events=>[], spamassassin=>{}, rspamd=>{}, dkim=>{}, dmarc=>{}, antivirus=>{},
        delivery=>{sent=>0,bounced=>0,deferred=>0,expired=>0}, classification=>{}, auth=>{}, tls=>[], legacy=>0,
    };
}
sub _normalize_message {
    my ($m,$qid)=@_; $m||={}; $m->{queue_id}||=$qid;
    $m->{recipients}||=[]; $m->{events}||=[]; $m->{spamassassin}||={}; $m->{rspamd}||={}; $m->{dkim}||={};
    $m->{dmarc}||={}; $m->{antivirus}||={}; $m->{delivery}||={}; $m->{classification}||={}; $m->{auth}||={}; $m->{tls}||=[];
    for my $k (qw(sent bounced deferred expired)) { $m->{delivery}{$k}||=0; }
    $m->{legacy}||=0; return $m;
}
sub _message {
    my ($self,$qid)=@_;
    return $self->{messages}{$qid} if $self->{messages}{$qid};
    my $m;
    if ($self->{load_message}) { $m=eval { $self->{load_message}->($qid) }; }
    $m=_normalize_message($m || _blank_message($qid),$qid);
    $self->{messages}{$qid}=$m;
    $self->{mid_to_qid}{$m->{message_id}}=$qid if defined($m->{message_id}) && $m->{message_id} ne '';
    return $m;
}
sub _resolve_mid {
    my ($self,$mid)=@_; return $self->{mid_to_qid}{$mid} if exists $self->{mid_to_qid}{$mid};
    if ($self->{resolve_message_id}) { my $q=$self->{resolve_message_id}->($mid); $self->{mid_to_qid}{$mid}=$q if $q; return $q; }
    return;
}
sub add_event {
    my ($self,$event)=@_; return if !$event;
    my $e=(blessed($event) && $event->can('as_hash')) ? $event->as_hash : $event;
    return if ref($e) ne 'HASH';
    my $qid=$e->{queue_id};
    if (($e->{type}||'') eq 'message_id' && $qid && defined $e->{message_id}) {
        $self->{mid_to_qid}{$e->{message_id}}=$qid; my $m=$self->_message($qid); $m->{message_id}=$e->{message_id};
        if (my $p=delete $self->{pending_by_mid}{$e->{message_id}}) { $self->_apply($m,$_) for @$p; }
    }
    if (($e->{type}||'') eq 'message_id_alias' && $qid && defined $e->{message_id}) {
        $self->{mid_to_qid}{$e->{message_id}}=$qid; my $m=$self->_message($qid);
        if (my $p=delete $self->{pending_by_mid}{$e->{message_id}}) { $self->_apply($m,$_) for @$p; }
    }
    if (!$qid && defined $e->{message_id}) { $qid=$self->_resolve_mid($e->{message_id}); }
    if ($qid && defined $e->{original_message_id} && $e->{original_message_id} ne '') { $self->{mid_to_qid}{$e->{original_message_id}}=$qid; }
    if ($qid) { my $m=$self->_message($qid); $self->_apply($m,$e); return $qid; }
    if (defined $e->{message_id}) { push @{$self->{pending_by_mid}{$e->{message_id}}},$e; }
    return;
}
sub _uniq_push { my ($a,$v)=@_; return if !defined $v; push @$a,$v if !grep { defined $_ && $_ eq $v } @$a; }
sub _apply {
    my ($self,$m,$e)=@_; push @{$m->{events}},$e;
    $m->{first_seen}=$e->{timestamp} if $e->{timestamp} && (!$m->{first_seen} || $e->{timestamp} lt $m->{first_seen});
    $m->{last_seen}=$e->{timestamp} if $e->{timestamp} && (!$m->{last_seen} || $e->{timestamp} gt $m->{last_seen});
    my $t=$e->{type}||''; my $src=$e->{source}||'';
    if ($t eq 'envelope') { @{$m}{qw(sender size nrcpt)}=@{$e}{qw(sender size nrcpt)}; }
    elsif ($t eq 'client') { $m->{client}={relay=>$e->{relay},host=>$e->{relay_host},ip=>$e->{relay_ip}}; if ($e->{sasl_username}) { $m->{auth}={success=>1,username=>$e->{sasl_username},method=>$e->{sasl_method}}; } }
    elsif ($t eq 'delivery') { _uniq_push($m->{recipients},$e->{recipient}); my $s=$e->{status}||''; $m->{delivery}{$s}++ if exists $m->{delivery}{$s}; $m->{last_dsn}=$e->{dsn} if defined $e->{dsn}; }
    elsif ($t eq 'transport_handoff') { _uniq_push($m->{recipients},$e->{recipient}); $m->{transport}=$e->{transport} if $e->{transport}; }
    elsif ($t eq 'milter_reject' || $t eq 'smtp_reject') { $m->{rejected}=1; $m->{reject_reason}=$e->{reason}; $m->{reject_dsn}=$e->{dsn}; $m->{sender}||=$e->{sender}; _uniq_push($m->{recipients},$e->{recipient}); $m->{rejected_as_spam}=1 if join(' ',grep {defined} ($e->{reason},$e->{rule})) =~ /spam|rspamd|spamassassin|dnsbl|blocked/i; }
    elsif ($t eq 'removed') { $m->{removed}=1; }
    elsif ($t eq 'smtp_auth') { $m->{auth}={success=>$e->{success}?1:0,username=>$e->{username},method=>$e->{method}}; }
    elsif ($t eq 'tls') { push @{$m->{tls}},$e; }
    elsif ($src eq 'spamassassin' && $t eq 'verdict') { $m->{spamassassin}={detected=>$e->{detected}?1:0,score=>$e->{score},required_score=>$e->{required_score},tests=>$e->{tests}||[],autolearn=>$e->{autolearn}}; }
    elsif ($src eq 'rspamd' && $t eq 'verdict') {
        $m->{rspamd}{action}=$e->{action} if defined $e->{action};
        $m->{rspamd}{score}=$e->{score} if defined $e->{score};
        $m->{rspamd}{required_score}=$e->{required_score} if defined $e->{required_score};
        for my $k (qw(symbols forced_action settings_id scan_time_ms dns_requests digest client_ip user sender recipients mime_recipients length evidence)) {
            $m->{rspamd}{$k}=$e->{$k} if exists $e->{$k} && defined $e->{$k};
        }
        $m->{sender}||=$e->{sender} if defined $e->{sender} && $e->{sender} ne '';
    }
    elsif ($src eq 'rspamd' && $t eq 'score') { $m->{rspamd}{detected}=$e->{detected}?1:0 if defined $e->{detected}; $m->{rspamd}{score}=$e->{score} if defined $e->{score}; }
    elsif ($src eq 'opendkim' && $t eq 'dkim_verification') { $m->{dkim}{verification}=$e->{result}; }
    elsif ($src eq 'opendkim' && $t eq 'dkim_signature') { @{$m->{dkim}}{qw(selector domain algorithm)}=@{$e}{qw(selector domain algorithm)}; }
    elsif ($src eq 'opendkim' && $t eq 'dkim_signing') { @{$m->{dkim}}{qw(signing selector domain)}=($e->{result},$e->{selector},$e->{domain}); }
    elsif ($src eq 'opendmarc' && $t eq 'dmarc_result') { @{$m->{dmarc}}{qw(domain result)}=@{$e}{qw(domain result)}; }
    elsif ($src eq 'opendmarc' && $t eq 'authentication_results') { @{$m->{dmarc}}{qw(spf dkim result)}=($e->{spf},$e->{dkim},$e->{dmarc}); }
    elsif ($t eq 'virus_verdict') { $m->{antivirus}={engine=>$src||'unknown',status=>$e->{status},normalized_status=>$e->{normalized_status},virus=>$e->{virus}}; }
    elsif ($src eq 'dovecot' && $t =~ /^lmtp/) { $m->{mailbox}=$e->{mailbox} if $e->{mailbox}; $m->{dovecot_user}=$e->{user} if $e->{user}; }
}
sub classify_message {
    my ($self,$m)=@_;
    my $sa=$m->{spamassassin}{detected}?1:0; my $a=lc($m->{rspamd}{action}||''); my $rd=$m->{rspamd}{detected}?1:0;
    $rd=1 if $a =~ /^(?:reject|add header|rewrite subject|soft reject)$/; $rd=0 if $a eq 'no action';
    my $del=($m->{delivery}{sent}||0)>0?1:0; my $rej=$m->{rejected}?1:0; my $sr=$m->{rejected_as_spam}?1:0; $sr=1 if $rej && $a eq 'reject';
    my $virus=(lc($m->{antivirus}{normalized_status}||'') =~ /virus|infected/ || lc($m->{antivirus}{status}||'') =~ /infected|found/)?1:0;
    my $sender_domain=''; $sender_domain=lc($1) if ($m->{sender}||'') =~ /@([^@>]+)$/; my $sender_local=$self->{local_domains}{$sender_domain}?1:0; my $rcpt_local=0; my $rcpt_external=0; for my $r (@{$m->{recipients}||[]}) { if ($r =~ /@([^@>]+)$/ && $self->{local_domains}{lc($1)}) { $rcpt_local=1 } else { $rcpt_external=1 } } my $direction='unknown'; if ($sender_local && $rcpt_external) { $direction='outbound' } elsif (!$sender_local && $rcpt_local) { $direction='inbound' } elsif ($sender_local && $rcpt_local) { $direction='internal' } elsif (!$sender_local && $rcpt_external && @{$m->{recipients}||[]}) { $direction='relay' } $m->{direction}=$direction;
    $m->{classification}={ delivered=>$del,rejected=>$rej,bounced=>(($m->{delivery}{bounced}||0)>0?1:0),deferred=>(($m->{delivery}{deferred}||0)>0?1:0),spam_detected=>($sa||$rd)?1:0,spam_rejected=>$sr,spam_delivered=>($del&&($sa||$rd))?1:0,spamassassin_detected=>$sa,rspamd_detected=>$rd,virus_detected=>$virus };
    return $m;
}
sub prune_cache {
    my ($self,$max)=@_; $max=0+$max; return 0 if $max<1;
    my @ids=keys %{$self->{messages}}; return 0 if @ids <= $max;
    @ids=sort { ($self->{messages}{$a}{last_seen}||$self->{messages}{$a}{first_seen}||'') cmp ($self->{messages}{$b}{last_seen}||$self->{messages}{$b}{first_seen}||'') } @ids;
    my $drop=@ids-$max; my $n=0;
    for my $qid (@ids[0..$drop-1]) { my $m=delete $self->{messages}{$qid}; next if !$m; if ($m->{message_id} && ($self->{mid_to_qid}{$m->{message_id}}||'') eq $qid) { delete $self->{mid_to_qid}{$m->{message_id}}; } $n++; }
    return $n;
}
sub finalize { my ($self)=@_; $self->classify_message($_) for values %{$self->{messages}}; return $self->{messages}; }
sub message_for { my ($self,$qid)=@_; my $m=$self->{messages}{$qid} or return; return $self->classify_message($m); }
sub messages { shift->{messages} }
1;
