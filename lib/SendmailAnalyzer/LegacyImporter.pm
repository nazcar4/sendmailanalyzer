package SendmailAnalyzer::LegacyImporter;
use strict;
use warnings;
use SendmailAnalyzer::LegacySource;
use SendmailAnalyzer::LegacyIdentity;
use SendmailAnalyzer::Event;

sub new { my ($class,%o)=@_; bless \%o,$class }
sub _ts { my ($y,$m,$d,$hms)=@_; $hms||='000000'; return sprintf('%04d-%02d-%02dT%s:%s:%s',$y,$m,$d,substr($hms,0,2),substr($hms,2,2),substr($hms,4,2)); }
sub _store_message { my ($storage,$m)=@_; $storage->upsert_message($m) if $m && $m->{queue_id}; }
sub _storage_has_message {
    my ($storage,$qid)=@_; return 0 if !$qid;
    if ($storage->can('message_exists')) { return $storage->message_exists($qid) ? 1:0; }
    if ($storage->can('dbh')) {
        my $dbh=eval { $storage->dbh };
        return 0 if !$dbh;
        my ($x)=eval { $dbh->selectrow_array('SELECT 1 FROM messages WHERE queue_id=? LIMIT 1',undef,$qid) };
        return $x ? 1:0;
    }
    return 0;
}
sub _base_message { my ($qid,$ts)=@_; return {queue_id=>$qid,first_seen=>$ts,last_seen=>$ts,recipients=>[],delivery=>{sent=>0,bounced=>0,deferred=>0,expired=>0},classification=>{},legacy=>1}; }
sub _agg_detail {
    my ($v)=@_; $v='' if !defined $v; $v="$v"; $v =~ s/[\x00-\x1f\x7f]+/ /g; $v =~ s/^\s+|\s+$//g; return substr($v,0,160);
}
sub _agg_inc {
    my ($agg,$date,$ts,$metric,$detail,$n)=@_; return if !$metric;
    my $hour=($ts||'') =~ /T(\d\d):/ ? $1 : '';
    $detail=_agg_detail($detail); $n=1 if !defined $n;
    $agg->{join("\0",$date||'', $hour, $metric, $detail)} += $n;
}
sub _flush_agg {
    my ($storage,$agg)=@_; return 0 if !$agg || !%$agg;
    my $n=0;
    for my $k (sort keys %$agg) {
        my ($day,$hour,$metric,$detail)=split /\0/,$k,4;
        if ($storage->can('set_legacy_aggregate')) { $storage->set_legacy_aggregate($day,$hour,$metric,$detail,$agg->{$k}); }
        $n += $agg->{$k};
    }
    %$agg=(); return $n;
}
sub _synthetic_aggregate {
    my ($agg,$type,$date,$ts,$e)=@_; $e||={};
    if ($type eq 'senders') { _agg_inc($agg,$date,$ts,'synthetic_envelope','',1); return; }
    if ($type eq 'recipient') {
        my $st=lc($e->{status}||''); _agg_inc($agg,$date,$ts,'recipient','',1);
        _agg_inc($agg,$date,$ts,'delivery_'.$st,'',1) if $st =~ /^(?:sent|bounced|deferred)$/;
        return;
    }
    if ($type eq 'spam') {
        _agg_inc($agg,$date,$ts,'spam_detected',$e->{rule},1);
        _agg_inc($agg,$date,$ts,'spam_rejected',$e->{rule},1) if ($e->{rule}||'') =~ /reject|blocked/i;
        return;
    }
    if ($type eq 'virus') { _agg_inc($agg,$date,$ts,'virus_detected',$e->{virus},1); return; }
    if ($type eq 'dsn') { _agg_inc($agg,$date,$ts,'dsn_events',$e->{status},1); return; }
    if ($type eq 'rejected') {
        my $detail=$e->{rule} || $e->{reason} || '';
        _agg_inc($agg,$date,$ts,'smtp_rejected',$detail,1);
        _agg_inc($agg,$date,$ts,'dnsbl_rejected',$detail,1) if join(' ',grep {defined} ($e->{rule},$e->{reason})) =~ /dnsbl|rbl|spamhaus|blocked\s+using/i;
        return;
    }
    if ($type eq 'spf_dkim') { _agg_inc($agg,$date,$ts,'authentication_result',join('/',grep {defined && $_ ne ''} ($e->{kind},$e->{status})),1); return; }
    if ($type eq 'postgrey') { _agg_inc($agg,$date,$ts,'greylist',$e->{status}||$e->{action},1); return; }
    if (($e->{type}||'') eq 'spam_detail') { _agg_inc($agg,$date,$ts,'spam_detected',$e->{engine},1); return; }
    _agg_inc($agg,$date,$ts,'legacy_'.$type,'',1);
}
sub _migration_guard {
    my ($storage,$lines)=@_; return if !$storage || !$storage->can('file'); return if !$lines || ($lines % 100000);
    my $db=$storage->file; return if !$db;
    my $wal=$db.'-wal'; my $wal_size=(-f $wal ? (-s $wal||0) : 0);
    my $limit=512*1024*1024;
    die sprintf("legacy migration safety guard: WAL grew to %.1f MiB before day commit (limit 512 MiB); active database was not replaced\n",$wal_size/1048576) if $wal_size>$limit;
}

sub import_tree {
    my ($self,$root,%opt)=@_; my $storage=$self->{storage} or die 'storage required';
    my %count=(files=>0,lines=>0,messages=>0,events=>0,normalized=>0,generic=>0,archives=>0,archived_files=>0,synthetic_skipped=>0);
    my $source=SendmailAnalyzer::LegacySource->new(root=>$root,progress=>$opt{progress});
    # Register the complete selected entry set before LegacyIdentity scans sender
    # files so the first archive access stages every needed member in one pass.
    my $entries=$source->entries(defined($opt{until})?(until=>$opt{until}):());
    my $identity=SendmailAnalyzer::LegacyIdentity->new(source=>$source,storage=>$storage,defined($opt{until})?(until=>$opt{until}):());
    $count{archives}=$source->archives; $count{archived_files}=$source->archived_entries;
    # Archive entries are staged lazily. Each monthly archive is expanded only
    # once for the selected files, then released after its final entry.
    my %archive_remaining;
    for my $e (@$entries) { $archive_remaining{$e->{archive}}++ if ($e->{kind}||'') eq 'archive'; }
    my $dbh=eval { $storage->can('dbh') ? $storage->dbh : undef };
    my $tx_capable=$dbh && eval { my $ac=$dbh->{AutoCommit}; 1 } ? 1 : 0;
    my %day_seen; my @day_order; my %real_message;
    for my $e (@$entries) { my $k=join('/',@{$e}{qw(host date)}); push @day_order,$k if !$day_seen{$k}++; }
    my $day_total=0+@day_order; my $day_index=0; my ($active_key,$active_label,$tx_active); my %day_agg; my $day_agg_lines=0;
    my $progress=$opt{progress};
    my $ok=eval {
    for my $entry (@$entries) {
        my ($host,$y,$m,$d,$type)=@{$entry}{qw(host year month day type)}; my $file_date=$entry->{date}; $count{files}++;
        my $day_key="$host/$file_date";
        if (!defined($active_key) || $day_key ne $active_key) {
            if (defined($active_key)) { $day_agg_lines+=_flush_agg($storage,\%day_agg); if ($tx_active) { $dbh->commit; $tx_active=0; eval { $dbh->do('PRAGMA wal_checkpoint(TRUNCATE)') }; } $progress->("Legacy import progress: day $day_index/$day_total $active_label committed (synthetic_aggregated=$day_agg_lines)") if $progress; $day_agg_lines=0; }
            $active_key=$day_key; $active_label="$host $file_date"; $day_index++;
            if ($tx_capable) { $dbh->begin_work; $tx_active=1; }
        }
        my $fh=$source->open_entry($entry); my $lineno=0;
        while (my $line=<$fh>) {
            $lineno++; chomp $line; next if $line eq ''; $count{lines}++; _migration_guard($storage,$count{lines}); if ($progress && ($count{lines} % 250000)==0) { $progress->("Legacy import scan: $active_label lines=$count{lines} synthetic_aggregated=$count{synthetic_skipped}"); }
            my ($time)=split /:/,$line,2; my $ts=_ts($y,$m,$d,$time); my ($e,$mm);

            if ($type eq 'senders') {
                my ($tm,$qid,$sender,$size,$nrcpt,$relay)=split /:/,$line,6; next if !$qid;
                # Upstream SendmailAnalyzer deliberately prefixes generated IDs
                # with FaKe when no real MTA Queue-ID exists (for example
                # NOQUEUE/check_relay rejections).  They are report identities,
                # not queued messages, and importing them as messages explodes
                # SQLite size and message counts.
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'envelope',queue_id=>$qid,sender=>$sender,size=>0+($size||0),nrcpt=>0+($nrcpt||0),relay=>$relay,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts); @{$mm}{qw(sender size nrcpt)}=($sender,0+($size||0),0+($nrcpt||0)); $mm->{client}={relay=>$relay};
            } elsif ($type eq 'recipient') {
                my ($tm,$qid,$rcpt,$relay,$status)=split /:/,$line,5; next if !$qid;
                my $st=lc($status||'');
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'delivery',queue_id=>$qid,recipient=>$rcpt,relay=>$relay,status=>$st,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts); $mm->{recipients}=[$rcpt]; $mm->{delivery}{sent}=1 if $st eq 'sent'; $mm->{delivery}{bounced}=1 if $st eq 'bounced'; $mm->{delivery}{deferred}=1 if $st eq 'deferred'; $mm->{classification}{delivered}=1 if $st eq 'sent';
            } elsif ($type eq 'spam') {
                my ($tm,$qid,$sender,$rcpt,$rule)=split /:/,$line,5; next if !$qid;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'spam',queue_id=>$qid,sender=>$sender,recipient=>$rcpt,rule=>$rule,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts); $mm->{sender}=$sender; $mm->{recipients}=[$rcpt]; $mm->{classification}{spam_detected}=1; $mm->{classification}{spam_rejected}=($rule||'')=~/reject|blocked/i?1:0;
            } elsif ($type eq 'virus') {
                my ($tm,$qid,$filename,$virus)=split /:/,$line,4; next if !$qid;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'virus_verdict',queue_id=>$qid,filename=>$filename,virus=>$virus,status=>'infected',normalized_status=>'infected',host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts); $mm->{antivirus}={engine=>'legacy',status=>'infected',normalized_status=>'infected',virus=>$virus}; $mm->{classification}{virus_detected}=1;
            } elsif ($type eq 'dsn') {
                my ($tm,$qid,$srcid,$status)=split /:/,$line,4; next if !$qid;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'dsn',queue_id=>$qid,source_queue_id=>$srcid,status=>$status,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts);
            } elsif ($type eq 'auth') {
                my ($tm,$id,$relay,$mech,$atype)=split /:/,$line,5;
                if (($id||'') eq 'anonymous' && ($atype||'') =~ /^TLS/i) {
                    $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'tls',direction=>'inbound',peer_host=>$relay,protocol=>$atype,cipher=>$mech,trust=>'anonymous',host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                } else {
                    $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'smtp_auth',username=>$id,peer_host=>$relay,method=>$mech,protocol=>$atype,success=>1,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                }
            } elsif ($type eq 'rejected') {
                my ($tm,$qid,$rule,$relay,$arg1,$status)=split /:/,$line,6; next if !$qid;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'smtp_reject',queue_id=>$qid,rule=>$rule,relay=>$relay,arg1=>$arg1,reason=>$status,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts); $mm->{rejected}=1; $mm->{reject_reason}=$status; $mm->{classification}{rejected}=1;
                $mm->{classification}{spam_rejected}=1 if join(' ',grep {defined} ($rule,$status)) =~ /spam|dnsbl|blocked/i;
            } elsif ($type eq 'spf_dkim') {
                my ($tm,$qid,$kind,$rule,$domain,$status)=split /:/,$line,6; next if !$qid;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'authentication_result',queue_id=>$qid,kind=>$kind,rule=>$rule,domain=>$domain,status=>$status,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                $mm=_base_message($qid,$ts);
                if (lc($kind||'') eq 'dkim') { $mm->{dkim}={verification=>$status,domain=>$domain}; }
            } elsif ($type eq 'starttls') {
                my ($tm,$summary)=split /:/,$line,2;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'starttls_aggregate',summary=>$summary,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
            } elsif ($type eq 'syserr') {
                my ($tm,$qid,$error)=split /:/,$line,3;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'system_error',queue_id=>$qid,error=>$error,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
            } elsif ($type eq 'other') {
                my ($tm,$detail)=split /:/,$line,2;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'other',detail=>$detail,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
            } elsif ($type eq 'postgrey') {
                # Upstream 9.4 format: Hour:Id:relay:from:to:action:status
                my ($tm,$id,$relay,$from,$to,$action,$status)=split /:/,$line,7;
                $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'greylist',queue_id=>$id,relay=>$relay,sender=>$from,recipient=>$to,action=>$action,status=>$status,host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
            } else {
                # With SPAM_DETAIL enabled, 9.4 stores one dynamic <engine>.dat file
                # per engine using: Hour:Id:type:score:cache:autolearn:spam.
                my @detail=split /:/,$line,7;
                if (@detail == 7 && ($detail[1]||'') ne '' && ($detail[2]||'') ne '' && lc($detail[2]) eq lc($type)) {
                    my ($tm,$qid,$engine,$score,$cache,$autolearn,$spam)=@detail;
                    $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'spam_detail',queue_id=>$qid,engine=>$engine,score=>$score,cache=>$cache,autolearn=>$autolearn,detail=>$spam,legacy_file=>$type.'.dat',host=>$host,timestamp=>$ts,raw=>$line,legacy=>1);
                    $mm=_base_message($qid,$ts); $mm->{classification}{spam_detected}=1; $count{normalized}++;
                } else {
                    my ($tm,$rest)=split /:/,$line,2; my ($qid)=defined($rest)?($rest =~ /^([A-Za-z0-9]{5,})(?=:|$)/):();
                    $e=SendmailAnalyzer::Event->new(source=>'legacy',type=>'legacy_'.$type,queue_id=>$qid,legacy_file=>$type.'.dat',host=>$host,timestamp=>$ts,raw=>$line,legacy=>1); $count{generic}++;
                }
            }
            # FaKe* is an upstream-generated report identity, not a real
            # Postfix Queue-ID.  Never materialize millions of these as SQLite
            # events/messages.  Preserve their historical statistics as bounded
            # per-day/per-hour aggregates and keep the original 9.4 files intact.
            if ($e && defined($e->{queue_id}) && $e->{queue_id} =~ /^(?:FaKe|NOQUEUE$)/) {
                _synthetic_aggregate(\%day_agg,$type,$file_date,$ts,$e->as_hash);
                $count{synthetic_skipped}++;
                next;
            }

            # Postfix Queue-IDs are not globally unique for all time. 9.4 stores
            # data by host/day, so preserve that generation identity internally when
            # the same Queue-ID is reused on another day or collides with existing
            # native v10 data. The original Queue-ID remains available for display.
            if ($e && defined($e->{queue_id}) && $e->{queue_id} ne '') {
                my $original=$e->{queue_id};
                my $internal=$identity->internal_qid($host,$file_date,$original);
                if ($internal ne $original) { $e->{legacy_queue_id}=$original; $e->{queue_id}=$internal; }
                if (defined($e->{source_queue_id}) && $e->{source_queue_id} ne '') {
                    my $src=$e->{source_queue_id};
                    $e->{legacy_source_queue_id}=$src;
                    $e->{source_queue_id}=$identity->internal_qid($host,$file_date,$src);
                }
            }
            if ($mm && defined($mm->{queue_id}) && $mm->{queue_id} ne '') {
                my $original=$mm->{queue_id};
                my $internal=$identity->internal_qid($host,$file_date,$original);
                if ($internal ne $original) { $mm->{queue_id}=$internal; $mm->{display_queue_id}=$original; }
            }

            # Only senders.dat is authoritative evidence that a real queued
            # message existed in 9.4.  Other .dat files are side-data.  In
            # particular rejected.dat can contain upstream synthetic FaKe* IDs
            # for NOQUEUE SMTP rejects; those must remain events/statistics and
            # must never become rows in messages.
            if ($type eq 'senders' && $mm && $mm->{queue_id}) {
                $real_message{$host}{$file_date}{$mm->{queue_id}}=1;
            }
            my $internal_qid=($mm && $mm->{queue_id}) ? $mm->{queue_id} : (($e && $e->{queue_id}) ? $e->{queue_id} : undef);
            my $is_real=$internal_qid && (
                $real_message{$host}{$file_date}{$internal_qid} ||
                _storage_has_message($storage,$internal_qid)
            );
            if ($type ne 'senders' && $mm && !$is_real) { $mm=undef; }
            if ($e) {
                $e->{legacy_locator}=$entry->{locator}.':'.$lineno;
                $storage->store_delivery_recipient($e->as_hash) if ($e->{type}||'') eq 'delivery' && $is_real;
                $storage->store_event($e); $count{events}++;
                $count{normalized}++ if $type =~ /^(?:senders|recipient|spam|virus|dsn|auth|rejected|spf_dkim|starttls|syserr|other|postgrey)$/;
            }
            if ($mm) { _store_message($storage,$mm); $count{messages}++ if $type eq 'senders'; }
        }
        $source->close_entry($fh,$entry);
        if (($entry->{kind}||'') eq 'archive') {
            my $a=$entry->{archive};
            $archive_remaining{$a}--;
            $source->release_archive($a) if $archive_remaining{$a}<=0;
        }
    }
    if (defined($active_key)) { $day_agg_lines+=_flush_agg($storage,\%day_agg); if ($tx_active) { $dbh->commit; $tx_active=0; eval { $dbh->do('PRAGMA wal_checkpoint(TRUNCATE)') }; } $progress->("Legacy import progress: day $day_index/$day_total $active_label committed (synthetic_aggregated=$day_agg_lines)") if $progress; $day_agg_lines=0; }
    1;
    };
    if (!$ok) {
        my $err=$@ || 'legacy import failed';
        eval { $dbh->rollback if $tx_active && $dbh };
        die $err;
    }
    $count{archive_extractions}=$source->archive_extractions;
    return \%count;
}
1;
