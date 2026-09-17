package SendmailAnalyzer::Storage::SQLite;
use strict;
use warnings;
use utf8;
use JSON::PP qw(encode_json decode_json);
use Digest::SHA qw(sha1_hex);
use Scalar::Util qw(blessed);

sub new {
    my ($class,%opt)=@_;
    eval { require DBI; require DBD::SQLite; 1 } or die "SQLite support requires Debian packages libdbi-perl and libdbd-sqlite3-perl: $@";
    my $file=$opt{file} || die 'DB file required';
    my $readonly=$opt{readonly}?1:0;
    my $dsn="dbi:SQLite:dbname=$file";
    my %attr=(RaiseError=>1,PrintError=>0,AutoCommit=>1,sqlite_unicode=>1);
    $attr{ReadOnly}=1 if $readonly;
    my $dbh=DBI->connect($dsn,'','',\%attr);
    $dbh->do('PRAGMA foreign_keys = ON');
    $dbh->do('PRAGMA busy_timeout = 5000');
    if (!$readonly) { $dbh->do('PRAGMA journal_mode = WAL'); $dbh->do('PRAGMA synchronous = NORMAL'); }
    my $self=bless {dbh=>$dbh,file=>$file,readonly=>$readonly},$class;
    $self->init_schema if !$readonly;
    my $cols=$dbh->selectall_arrayref('PRAGMA table_info(messages)',{Slice=>{}});
    $self->{has_display_queue_id}=scalar(grep { ($_->{name}||'') eq 'display_queue_id' } @$cols) ? 1 : 0;
    return $self;
}
sub dbh { shift->{dbh} }
sub file { shift->{file} }
sub init_schema {
    my ($self)=@_; my $d=$self->{dbh};
    $d->do(q{CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)});
    $d->do(q{CREATE TABLE IF NOT EXISTS messages (
      queue_id TEXT PRIMARY KEY, display_queue_id TEXT, message_id TEXT, first_seen TEXT, last_seen TEXT, sender TEXT, size INTEGER, nrcpt INTEGER,
      client_host TEXT, client_ip TEXT, delivered_count INTEGER NOT NULL DEFAULT 0, bounced_count INTEGER NOT NULL DEFAULT 0,
      deferred_count INTEGER NOT NULL DEFAULT 0, rejected INTEGER NOT NULL DEFAULT 0, reject_reason TEXT, reject_dsn TEXT,
      spam_detected INTEGER NOT NULL DEFAULT 0, spam_rejected INTEGER NOT NULL DEFAULT 0, spam_delivered INTEGER NOT NULL DEFAULT 0,
      sa_detected INTEGER NOT NULL DEFAULT 0, sa_score REAL, rspamd_detected INTEGER NOT NULL DEFAULT 0, rspamd_action TEXT, rspamd_score REAL,
      rspamd_required_score REAL, rspamd_forced_action TEXT, rspamd_settings_id TEXT, rspamd_scan_time_ms REAL, rspamd_dns_requests INTEGER,
      dkim_result TEXT, dkim_domain TEXT, dkim_selector TEXT, dmarc_result TEXT, dmarc_domain TEXT, av_status TEXT, virus_name TEXT,
      auth_user TEXT, auth_method TEXT, direction TEXT, removed INTEGER NOT NULL DEFAULT 0, legacy INTEGER NOT NULL DEFAULT 0
    )});
    # Message-ID is correlation evidence, not a globally unique identifier.
    # The same RFC Message-ID can legitimately appear under multiple Postfix Queue-IDs.
    $d->do(q{DROP INDEX IF EXISTS idx_messages_mid});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_messages_mid ON messages(message_id) WHERE message_id IS NOT NULL AND message_id <> ''});
    $d->do(q{CREATE TABLE IF NOT EXISTS message_ids (
      message_id TEXT NOT NULL, queue_id TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'alias', first_seen TEXT,
      PRIMARY KEY(message_id,queue_id)
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_message_ids_qid ON message_ids(queue_id)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_messages_seen ON messages(last_seen)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_messages_first_seen ON messages(first_seen)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender)});
    $d->do(q{CREATE TABLE IF NOT EXISTS recipients (
      id INTEGER PRIMARY KEY AUTOINCREMENT, queue_id TEXT NOT NULL, recipient TEXT, status TEXT, dsn TEXT, relay TEXT, timestamp TEXT,
      UNIQUE(queue_id,recipient,status,dsn,relay,timestamp)
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_rcpt_addr ON recipients(recipient)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_rcpt_qid ON recipients(queue_id)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_rcpt_time ON recipients(timestamp)});
    $d->do(q{CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT NOT NULL UNIQUE, timestamp TEXT, host TEXT, queue_id TEXT, message_id TEXT,
      source TEXT NOT NULL, type TEXT NOT NULL, data_json TEXT NOT NULL, raw TEXT
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_events_time ON events(timestamp)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_events_src_type ON events(source,type)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_events_qid ON events(queue_id)});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_events_mid ON events(message_id)});
    $d->do(q{CREATE TABLE IF NOT EXISTS auth_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, host TEXT, source TEXT, protocol TEXT, username TEXT, method TEXT,
      client_ip TEXT, success INTEGER NOT NULL, detail TEXT, fingerprint TEXT UNIQUE
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_auth_time ON auth_events(timestamp)});
    $d->do(q{CREATE TABLE IF NOT EXISTS tls_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, host TEXT, direction TEXT, peer_host TEXT, peer_ip TEXT, protocol TEXT,
      cipher TEXT, bits TEXT, trust TEXT, fingerprint TEXT UNIQUE
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_tls_time ON tls_events(timestamp)});
    $d->do(q{CREATE TABLE IF NOT EXISTS legacy_aggregates (
      day TEXT NOT NULL, hour TEXT NOT NULL DEFAULT '', metric TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', count INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(day,hour,metric,detail)
    )});
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_legacy_agg_metric_day ON legacy_aggregates(metric,day)});
    $d->do(q{CREATE TABLE IF NOT EXISTS collector_state (source TEXT PRIMARY KEY, inode INTEGER, offset INTEGER, updated_at TEXT)});
    my $cols=$d->selectall_arrayref('PRAGMA table_info(messages)',{Slice=>{}}); my %have=map { $_->{name}=>1 } @$cols; $d->do('ALTER TABLE messages ADD COLUMN direction TEXT') if !$have{direction};
    if (!$have{display_queue_id}) { $d->do('ALTER TABLE messages ADD COLUMN display_queue_id TEXT'); $have{display_queue_id}=1; }
    $d->do(q{CREATE INDEX IF NOT EXISTS idx_messages_display_qid ON messages(display_queue_id) WHERE display_queue_id IS NOT NULL AND display_queue_id <> ''});
    my %extra=(rspamd_required_score=>'REAL',rspamd_forced_action=>'TEXT',rspamd_settings_id=>'TEXT',rspamd_scan_time_ms=>'REAL',rspamd_dns_requests=>'INTEGER');
    for my $c (sort keys %extra) { $d->do("ALTER TABLE messages ADD COLUMN $c $extra{$c}") if !$have{$c}; }
    # 10.0.0-10.0.2 could create recipient placeholder rows with NULL status.
    # They carry no delivery fact and can double-count recipient statistics.
    $d->do(q{DELETE FROM recipients WHERE status IS NULL});
    $d->do(q{INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','8')});
}
sub _fingerprint {
    my ($self,$e)=@_; return sha1_hex(join("\0", map { defined $_ ? $_ : '' } @{$e}{qw(timestamp host source type queue_id message_id raw legacy_locator)}));
}
sub _changes {
    my ($self)=@_;
    my ($n)=$self->{dbh}->selectrow_array('SELECT changes()');
    return 0+($n||0);
}
sub set_legacy_aggregate {
    my ($self,$day,$hour,$metric,$detail,$count)=@_; return 0 if !$day || !$metric;
    $hour='' if !defined $hour; $detail='' if !defined $detail; $count=0+($count||0);
    $self->{dbh}->do(q{INSERT INTO legacy_aggregates(day,hour,metric,detail,count) VALUES(?,?,?,?,?)
      ON CONFLICT(day,hour,metric,detail) DO UPDATE SET count=excluded.count},undef,$day,$hour,$metric,$detail,$count);
    return $count;
}
sub _legacy_agg_sum {
    my ($self,$metric,$from,$to)=@_; return 0 if !$metric;
    my (@w,@b); push @w,'metric=?'; push @b,$metric;
    if (defined($from) && $from ne '') { push @w,'day >= ?'; push @b,substr($from,0,10); }
    if (defined($to) && $to ne '') { push @w,'day <= ?'; push @b,substr($to,0,10); }
    my ($n)=$self->{dbh}->selectrow_array('SELECT COALESCE(SUM(count),0) FROM legacy_aggregates WHERE '.join(' AND ',@w),undef,@b);
    return 0+($n||0);
}
sub _legacy_agg_by_day {
    my ($self,$metric,$from_day,$to_day)=@_; my @w=('metric=?'); my @b=($metric);
    if ($from_day) { push @w,'day>=?'; push @b,$from_day; }
    if ($to_day) { push @w,'day<=?'; push @b,$to_day; }
    return $self->{dbh}->selectall_arrayref('SELECT day,COALESCE(SUM(count),0) count FROM legacy_aggregates WHERE '.join(' AND ',@w).' GROUP BY day ORDER BY day',{Slice=>{}},@b);
}
sub _legacy_agg_by_hour {
    my ($self,$metric,$day)=@_;
    return $self->{dbh}->selectall_arrayref(q{SELECT hour,COALESCE(SUM(count),0) count FROM legacy_aggregates WHERE metric=? AND day=? GROUP BY hour ORDER BY hour},{Slice=>{}},$metric,$day);
}

sub _availability_periods {
    my ($self,$from,$to,$length)=@_;
    return {} if !$from || !$to || !$length;
    my %seen;
    for my $src (
        ['messages','first_seen'],
        ['events','timestamp'],
        ['auth_events','timestamp'],
        ['tls_events','timestamp'],
    ) {
        my ($table,$column)=@$src;
        my $sql="SELECT DISTINCT substr($column,1,$length) FROM $table WHERE $column >= ? AND $column < ? AND $column IS NOT NULL";
        my $rows=$self->{dbh}->selectcol_arrayref($sql,undef,$from,$to);
        $seen{$_}=1 for grep { defined($_) && $_ ne '' } @$rows;
    }
    my $from_day=substr($from,0,10);
    my $to_day=substr($to,0,10);
    my $rows=$self->{dbh}->selectcol_arrayref("SELECT DISTINCT substr(day,1,$length) FROM legacy_aggregates WHERE day >= ? AND day < ?",undef,$from_day,$to_day);
    $seen{$_}=1 for grep { defined($_) && $_ ne '' } @$rows;
    return \%seen;
}
sub available_days_for_month {
    my ($self,$ym)=@_;
    return {} if !defined($ym) || $ym !~ /\A(\d{4})-(\d{2})\z/;
    my ($y,$m)=($1,0+$2); return {} if $m<1 || $m>12;
    my ($ny,$nm)=($y,$m+1); if($nm==13){$nm=1;$ny++}
    my $from=sprintf('%04d-%02d-01T00:00:00',$y,$m);
    my $to=sprintf('%04d-%02d-01T00:00:00',$ny,$nm);
    return $self->_availability_periods($from,$to,10);
}
sub available_months_for_year {
    my ($self,$year)=@_;
    return {} if !defined($year) || $year !~ /\A\d{4}\z/;
    my $from=sprintf('%04d-01-01T00:00:00',$year);
    my $to=sprintf('%04d-01-01T00:00:00',$year+1);
    return $self->_availability_periods($from,$to,7);
}
sub day_has_data {
    my ($self,$day)=@_;
    return 0 if !defined($day) || $day !~ /\A(\d{4})-(\d{2})-(\d{2})\z/;
    my ($y,$m,$d)=($1,0+$2,0+$3);
    require Time::Local;
    my $t=eval { Time::Local::timelocal(0,0,12,$d,$m-1,$y) }; return 0 if !defined $t;
    my @n=localtime($t+86400);
    my $next=sprintf('%04d-%02d-%02d',$n[5]+1900,$n[4]+1,$n[3]);
    my $a=$self->_availability_periods($day.'T00:00:00',$next.'T00:00:00',10);
    return $a->{$day}?1:0;
}
sub month_has_data {
    my ($self,$ym)=@_;
    my $a=$self->available_days_for_month($ym);
    return scalar(keys %$a)?1:0;
}
sub store_event {
    my ($self,$event)=@_; my $e=(blessed($event) && $event->can('as_hash')) ? $event->as_hash : $event;
    die 'event must be an object with as_hash() or a hash reference' if ref($e) ne 'HASH';
    my $fp=$self->_fingerprint($e); my %copy=%$e; delete $copy{raw};
    my $sth=$self->{dbh}->prepare(q{INSERT OR IGNORE INTO events(fingerprint,timestamp,host,queue_id,message_id,source,type,data_json,raw) VALUES(?,?,?,?,?,?,?,?,?)});
    $sth->execute($fp,$e->{timestamp},$e->{host},$e->{queue_id},$e->{message_id},$e->{source}||'unknown',$e->{type}||'unknown',encode_json(\%copy),$e->{raw});
    my $inserted=$self->_changes ? 1 : 0;
    if (defined($e->{message_id}) && $e->{message_id} ne '') {
        my $qid=$e->{queue_id} || $self->resolve_message_id($e->{message_id});
        my $kind=(($e->{type}||'') eq 'message_id') ? 'canonical' : (($e->{type}||'') eq 'message_id_alias' ? ($e->{alias_kind}||'alias') : 'evidence');
        $self->link_message_id($e->{message_id},$qid,$kind,$e->{timestamp}) if $qid;
        $self->link_message_id($e->{original_message_id},$qid,'spamd-original',$e->{timestamp}) if $qid && defined($e->{original_message_id}) && $e->{original_message_id} ne '';
    }
    if (($e->{type}||'') eq 'smtp_auth' || (($e->{source}||'') eq 'dovecot' && ($e->{type}||'') eq 'login') || (($e->{type}||'') eq 'client' && $e->{sasl_username})) {
        my $afp='auth:'.$fp; my $success=(($e->{type}||'') eq 'client' && $e->{sasl_username}) ? 1 : ($e->{success}?1:0);
        my $proto=$e->{protocol} || ((($e->{type}||'') eq 'client')?'smtp':undef);
        $self->{dbh}->do(q{INSERT OR IGNORE INTO auth_events(timestamp,host,source,protocol,username,method,client_ip,success,detail,fingerprint) VALUES(?,?,?,?,?,?,?,?,?,?)},undef,$e->{timestamp},$e->{host},$e->{source},$proto,$e->{username}||$e->{user}||$e->{sasl_username},$e->{method}||$e->{sasl_method},$e->{peer_ip}||$e->{remote_ip}||$e->{relay_ip},$success,$e->{detail},$afp);
    }
    if (($e->{type}||'') eq 'tls') {
        my $tfp='tls:'.$fp; $self->{dbh}->do(q{INSERT OR IGNORE INTO tls_events(timestamp,host,direction,peer_host,peer_ip,protocol,cipher,bits,trust,fingerprint) VALUES(?,?,?,?,?,?,?,?,?,?)},undef,$e->{timestamp},$e->{host},$e->{direction},$e->{peer_host},$e->{peer_ip},$e->{protocol},$e->{cipher},$e->{bits},$e->{trust},$tfp);
    }
    return $inserted;
}
sub upsert_message {
    my ($self,$m)=@_; return if !$m || !$m->{queue_id};
    my $c=$m->{classification}||{}; my $cl=$m->{client}||{}; my $sa=$m->{spamassassin}||{}; my $r=$m->{rspamd}||{}; my $dk=$m->{dkim}||{}; my $dm=$m->{dmarc}||{}; my $av=$m->{antivirus}||{}; my $au=$m->{auth}||{};
    $self->{dbh}->do(q{INSERT INTO messages(queue_id,message_id,first_seen,last_seen,sender,size,nrcpt,client_host,client_ip,delivered_count,bounced_count,deferred_count,rejected,reject_reason,reject_dsn,spam_detected,spam_rejected,spam_delivered,sa_detected,sa_score,rspamd_detected,rspamd_action,rspamd_score,dkim_result,dkim_domain,dkim_selector,dmarc_result,dmarc_domain,av_status,virus_name,auth_user,auth_method,direction,removed,legacy)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(queue_id) DO UPDATE SET
       message_id=COALESCE(excluded.message_id,messages.message_id), first_seen=CASE WHEN messages.first_seen IS NULL THEN excluded.first_seen WHEN excluded.first_seen IS NULL THEN messages.first_seen ELSE MIN(messages.first_seen,excluded.first_seen) END, last_seen=CASE WHEN messages.last_seen IS NULL THEN excluded.last_seen WHEN excluded.last_seen IS NULL THEN messages.last_seen ELSE MAX(messages.last_seen,excluded.last_seen) END, sender=COALESCE(excluded.sender,messages.sender), size=COALESCE(excluded.size,messages.size), nrcpt=COALESCE(excluded.nrcpt,messages.nrcpt), client_host=COALESCE(excluded.client_host,messages.client_host), client_ip=COALESCE(excluded.client_ip,messages.client_ip), delivered_count=MAX(messages.delivered_count,excluded.delivered_count), bounced_count=MAX(messages.bounced_count,excluded.bounced_count), deferred_count=MAX(messages.deferred_count,excluded.deferred_count), rejected=MAX(messages.rejected,excluded.rejected), reject_reason=COALESCE(excluded.reject_reason,messages.reject_reason), reject_dsn=COALESCE(excluded.reject_dsn,messages.reject_dsn), spam_detected=MAX(messages.spam_detected,excluded.spam_detected), spam_rejected=MAX(messages.spam_rejected,excluded.spam_rejected), spam_delivered=MAX(messages.spam_delivered,excluded.spam_delivered), sa_detected=MAX(messages.sa_detected,excluded.sa_detected), sa_score=COALESCE(excluded.sa_score,messages.sa_score), rspamd_detected=MAX(messages.rspamd_detected,excluded.rspamd_detected), rspamd_action=COALESCE(excluded.rspamd_action,messages.rspamd_action), rspamd_score=COALESCE(excluded.rspamd_score,messages.rspamd_score), dkim_result=COALESCE(excluded.dkim_result,messages.dkim_result), dkim_domain=COALESCE(excluded.dkim_domain,messages.dkim_domain), dkim_selector=COALESCE(excluded.dkim_selector,messages.dkim_selector), dmarc_result=COALESCE(excluded.dmarc_result,messages.dmarc_result), dmarc_domain=COALESCE(excluded.dmarc_domain,messages.dmarc_domain), av_status=COALESCE(excluded.av_status,messages.av_status), virus_name=COALESCE(excluded.virus_name,messages.virus_name), auth_user=COALESCE(excluded.auth_user,messages.auth_user), auth_method=COALESCE(excluded.auth_method,messages.auth_method), direction=COALESCE(NULLIF(excluded.direction,'unknown'),messages.direction), removed=MAX(messages.removed,excluded.removed), legacy=MAX(messages.legacy,excluded.legacy)},undef,
      $m->{queue_id},$m->{message_id},$m->{first_seen},$m->{last_seen},$m->{sender},$m->{size},$m->{nrcpt},$cl->{host},$cl->{ip},$m->{delivery}{sent}||0,$m->{delivery}{bounced}||0,$m->{delivery}{deferred}||0,$c->{rejected}||0,$m->{reject_reason},$m->{reject_dsn},$c->{spam_detected}||0,$c->{spam_rejected}||0,$c->{spam_delivered}||0,$c->{spamassassin_detected}||0,$sa->{score},$c->{rspamd_detected}||0,$r->{action},$r->{score},$dk->{verification}||$dk->{signing},$dk->{domain},$dk->{selector},$dm->{result},$dm->{domain},$av->{status}||$av->{normalized_status},$av->{virus},$au->{username},$au->{method},$m->{direction},$m->{removed}?1:0,$m->{legacy}?1:0);
    $self->{dbh}->do(q{UPDATE messages SET
      rspamd_required_score=COALESCE(?,rspamd_required_score),
      rspamd_forced_action=COALESCE(?,rspamd_forced_action),
      rspamd_settings_id=COALESCE(?,rspamd_settings_id),
      rspamd_scan_time_ms=COALESCE(?,rspamd_scan_time_ms),
      rspamd_dns_requests=COALESCE(?,rspamd_dns_requests)
      WHERE queue_id=?},undef,$r->{required_score},$r->{forced_action},$r->{settings_id},$r->{scan_time_ms},$r->{dns_requests},$m->{queue_id});
    if (defined($m->{display_queue_id}) && $m->{display_queue_id} ne '') {
        $self->{dbh}->do(q{UPDATE messages SET display_queue_id=COALESCE(display_queue_id,?) WHERE queue_id=?},undef,$m->{display_queue_id},$m->{queue_id});
    }
    $self->_sync_delivery_counts($m->{queue_id});
    $self->_recompute_derived($m->{queue_id});
}
sub message_exists {
    my ($self,$qid)=@_; return 0 if !$qid;
    my ($x)=$self->{dbh}->selectrow_array('SELECT 1 FROM messages WHERE queue_id=? LIMIT 1',undef,$qid);
    return $x ? 1:0;
}
sub _sync_delivery_counts {
    my ($self,$qid)=@_; return if !$qid;
    my $r=$self->{dbh}->selectrow_hashref(q{SELECT
      SUM(CASE WHEN lower(COALESCE(status,''))='sent' THEN 1 ELSE 0 END) sent,
      SUM(CASE WHEN lower(COALESCE(status,''))='bounced' THEN 1 ELSE 0 END) bounced,
      SUM(CASE WHEN lower(COALESCE(status,''))='deferred' THEN 1 ELSE 0 END) deferred
      FROM recipients WHERE queue_id=?},undef,$qid) || {};
    $self->{dbh}->do(q{UPDATE messages SET delivered_count=MAX(delivered_count,?), bounced_count=MAX(bounced_count,?), deferred_count=MAX(deferred_count,?) WHERE queue_id=?},undef,0+($r->{sent}||0),0+($r->{bounced}||0),0+($r->{deferred}||0),$qid);
}
sub _recompute_derived {
    my ($self,$qid)=@_; return if !$qid;
    $self->{dbh}->do(q{UPDATE messages SET
      spam_delivered=CASE WHEN delivered_count>0 AND spam_detected=1 THEN 1 ELSE spam_delivered END,
      spam_rejected=CASE WHEN rejected=1 AND (spam_rejected=1 OR lower(COALESCE(rspamd_action,''))='reject') THEN 1 ELSE spam_rejected END
      WHERE queue_id=?},undef,$qid);
}
sub store_delivery_recipient {
    my ($self,$e)=@_; return if !$e->{queue_id};
    $self->{dbh}->do(q{INSERT OR IGNORE INTO recipients(queue_id,recipient,status,dsn,relay,timestamp) VALUES(?,?,?,?,?,?)},undef,@{$e}{qw(queue_id recipient status dsn relay timestamp)});
    $self->_sync_delivery_counts($e->{queue_id});
    $self->_recompute_derived($e->{queue_id});
}
sub resolve_message_id {
    my ($self,$mid)=@_;
    my $qid=$self->{dbh}->selectrow_array(q{SELECT queue_id FROM message_ids WHERE message_id=? ORDER BY COALESCE(first_seen,'') DESC LIMIT 1},undef,$mid);
    return $qid if $qid;
    return $self->{dbh}->selectrow_array('SELECT queue_id FROM messages WHERE message_id=? ORDER BY COALESCE(last_seen,first_seen) DESC LIMIT 1',undef,$mid);
}
sub link_message_id {
    my ($self,$mid,$qid,$kind,$ts)=@_; return 0 if !$mid || !$qid; $kind||='alias';
    $self->{dbh}->do(q{INSERT OR IGNORE INTO message_ids(message_id,queue_id,kind,first_seen) VALUES(?,?,?,?)},undef,$mid,$qid,$kind,$ts);
    my $n=$self->_changes;
    $self->{dbh}->do(q{UPDATE events SET queue_id=? WHERE message_id=? AND (queue_id IS NULL OR queue_id='')},undef,$qid,$mid);
    return $n + $self->_changes;
}
sub load_classifier_message {
    my ($self,$qid)=@_; return if !$qid;
    my $r=$self->{dbh}->selectrow_hashref('SELECT * FROM messages WHERE queue_id=?',undef,$qid) or return;
    my $rc=$self->{dbh}->selectcol_arrayref(q{SELECT DISTINCT recipient FROM recipients WHERE queue_id=? AND recipient IS NOT NULL AND recipient<>''},undef,$qid) || [];
    return {
      queue_id=>$r->{queue_id}, message_id=>$r->{message_id}, first_seen=>$r->{first_seen}, last_seen=>$r->{last_seen}, sender=>$r->{sender}, size=>$r->{size}, nrcpt=>$r->{nrcpt},
      client=>{host=>$r->{client_host},ip=>$r->{client_ip}}, recipients=>$rc, events=>[],
      delivery=>{sent=>0+($r->{delivered_count}||0),bounced=>0+($r->{bounced_count}||0),deferred=>0+($r->{deferred_count}||0),expired=>0},
      classification=>{delivered=>($r->{delivered_count}||0)>0?1:0,rejected=>$r->{rejected}?1:0,spam_detected=>$r->{spam_detected}?1:0,spam_rejected=>$r->{spam_rejected}?1:0,spam_delivered=>$r->{spam_delivered}?1:0},
      spamassassin=>{detected=>$r->{sa_detected}?1:0,score=>$r->{sa_score}},
      rspamd=>{detected=>$r->{rspamd_detected}?1:0,action=>$r->{rspamd_action},score=>$r->{rspamd_score},required_score=>$r->{rspamd_required_score},forced_action=>$r->{rspamd_forced_action},settings_id=>$r->{rspamd_settings_id},scan_time_ms=>$r->{rspamd_scan_time_ms},dns_requests=>$r->{rspamd_dns_requests}},
      dkim=>{verification=>$r->{dkim_result},domain=>$r->{dkim_domain},selector=>$r->{dkim_selector}},
      dmarc=>{result=>$r->{dmarc_result},domain=>$r->{dmarc_domain}}, antivirus=>{status=>$r->{av_status},virus=>$r->{virus_name}},
      auth=>{username=>$r->{auth_user},method=>$r->{auth_method}}, direction=>$r->{direction}, removed=>$r->{removed}?1:0, legacy=>$r->{legacy}?1:0,
      rejected=>$r->{rejected}?1:0, reject_reason=>$r->{reject_reason}, reject_dsn=>$r->{reject_dsn}, tls=>[],
    };
}
sub get_state { my ($self,$source)=@_; return $self->{dbh}->selectrow_hashref('SELECT * FROM collector_state WHERE source=?',undef,$source); }
sub set_state { my ($self,$source,$inode,$offset,$ts)=@_; $self->{dbh}->do(q{INSERT INTO collector_state(source,inode,offset,updated_at) VALUES(?,?,?,?) ON CONFLICT(source) DO UPDATE SET inode=excluded.inode,offset=excluded.offset,updated_at=excluded.updated_at},undef,$source,$inode,$offset,$ts); }
sub stats {
    my ($self,$since)=@_;
    return $self->stats_range($since,undef);
}
sub stats_range {
    my ($self,$from,$to)=@_;
    my (@mw,@mb,@ew,@eb);
    if (defined($from) && $from ne '') { push @mw,'first_seen >= ?'; push @mb,$from; push @ew,'timestamp >= ?'; push @eb,$from; }
    if (defined($to) && $to ne '') { push @mw,'first_seen <= ?'; push @mb,$to; push @ew,'timestamp <= ?'; push @eb,$to; }
    my $mwhere=@mw?'WHERE '.join(' AND ',@mw):'';
    my $eprefix=@ew?'WHERE '.join(' AND ',@ew).' AND ':'WHERE ';
    my $row=$self->{dbh}->selectrow_hashref("SELECT COUNT(*) messages, COALESCE(SUM(delivered_count),0) delivered, COALESCE(SUM(bounced_count),0) bounced, COALESCE(SUM(deferred_count),0) deferred, COALESCE(SUM(rejected),0) rejected, COALESCE(SUM(spam_detected),0) spam_detected, COALESCE(SUM(spam_rejected),0) spam_rejected, COALESCE(SUM(spam_delivered),0) spam_delivered, SUM(CASE WHEN direction='inbound' THEN 1 ELSE 0 END) inbound, SUM(CASE WHEN direction='outbound' THEN 1 ELSE 0 END) outbound, SUM(CASE WHEN direction='internal' THEN 1 ELSE 0 END) internal, SUM(CASE WHEN direction='relay' THEN 1 ELSE 0 END) relay, SUM(CASE WHEN direction IS NULL OR direction='' OR direction='unknown' THEN 1 ELSE 0 END) unknown, COALESCE(SUM(size),0) bytes FROM messages $mwhere",undef,@mb);
    my $dns=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM events ${eprefix}source='postscreen' AND type='dnsbl_reject'",undef,@eb);
    my $smtprej=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM events ${eprefix}type='smtp_reject'",undef,@eb);
    my $authfail=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM auth_events ".(@ew?'WHERE '.join(' AND ',@ew).' AND ':'WHERE ')."success=0",undef,@eb);
    my $authok=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM auth_events ".(@ew?'WHERE '.join(' AND ',@ew).' AND ':'WHERE ')."success=1",undef,@eb);
    my $tls=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM tls_events".(@ew?' WHERE '.join(' AND ',@ew):''),undef,@eb);
    my $dsn=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM events ${eprefix}type='dsn'",undef,@eb);
    my $virus=$self->{dbh}->selectrow_array("SELECT COUNT(*) FROM messages ".(@mw?'WHERE '.join(' AND ',@mw).' AND ':'WHERE ')."lower(COALESCE(av_status,'')) NOT IN ('','clean','ok')",undef,@mb);
    $row->{dnsbl_rejected}=0+$dns; $row->{smtp_rejected}=0+$smtprej; $row->{auth_failures}=0+$authfail; $row->{auth_success}=0+$authok;
    $row->{smtp_rejected}=0+$smtprej+$self->_legacy_agg_sum('smtp_rejected',$from,$to);
    $row->{dnsbl_rejected}=0+$dns+$self->_legacy_agg_sum('dnsbl_rejected',$from,$to);
    $row->{spam_detected}=0+($row->{spam_detected}||0)+$self->_legacy_agg_sum('spam_detected',$from,$to);
    $row->{spam_rejected}=0+($row->{spam_rejected}||0)+$self->_legacy_agg_sum('spam_rejected',$from,$to);
    $row->{delivered}=0+($row->{delivered}||0)+$self->_legacy_agg_sum('delivery_sent',$from,$to);
    $row->{bounced}=0+($row->{bounced}||0)+$self->_legacy_agg_sum('delivery_bounced',$from,$to);
    $row->{deferred}=0+($row->{deferred}||0)+$self->_legacy_agg_sum('delivery_deferred',$from,$to);
    $row->{tls_connections}=0+$tls;
    $row->{dsn_events}=0+$dsn+$self->_legacy_agg_sum('dsn_events',$from,$to);
    $row->{virus_detected}=0+$virus+$self->_legacy_agg_sum('virus_detected',$from,$to); return $row;
}
sub recent_messages {
    my ($self,%opt)=@_; my $limit=defined($opt{limit})?0+$opt{limit}:100; $limit=100 if $limit<1; $limit=500 if $limit>500; my $q=$opt{q}||''; my @w; my @b;
    if ($q ne '') {
        my $p="%$q%";
        if ($self->{has_display_queue_id}) { push @w, q{(m.queue_id LIKE ? OR m.display_queue_id LIKE ? OR m.message_id LIKE ? OR m.sender LIKE ? OR EXISTS (SELECT 1 FROM recipients r WHERE r.queue_id=m.queue_id AND r.recipient LIKE ?))}; push @b,($p)x5; }
        else { push @w, q{(m.queue_id LIKE ? OR m.message_id LIKE ? OR m.sender LIKE ? OR EXISTS (SELECT 1 FROM recipients r WHERE r.queue_id=m.queue_id AND r.recipient LIKE ?))}; push @b,($p)x4; }
    }
    if (defined($opt{direction}) && $opt{direction} =~ /^(?:inbound|outbound|internal|relay|unknown)$/) { push @w,'m.direction=?'; push @b,$opt{direction}; }
    if (defined($opt{from}) && $opt{from} ne '') { push @w,'m.first_seen >= ?'; push @b,$opt{from}; }
    if (defined($opt{to}) && $opt{to} ne '') { push @w,'m.first_seen <= ?'; push @b,$opt{to}; }
    if ($opt{spam}) { push @w,'m.spam_detected=1'; }
    if ($opt{rejected}) { push @w,'m.rejected=1'; }
    if ($opt{virus}) { push @w,q{lower(COALESCE(m.av_status,'')) NOT IN ('','clean','ok')}; }
    my $where=@w?'WHERE '.join(' AND ',@w):'';
    my $sth=$self->{dbh}->prepare("SELECT m.* FROM messages m $where ORDER BY COALESCE(m.last_seen,m.first_seen) DESC LIMIT ?"); $sth->execute(@b,$limit); return $sth->fetchall_arrayref({});
}
sub message_detail {
    my ($self,$qid)=@_;
    my $m=$self->{dbh}->selectrow_hashref('SELECT * FROM messages WHERE queue_id=?',undef,$qid);
    $m ||= $self->{dbh}->selectrow_hashref(q{SELECT * FROM messages WHERE display_queue_id=? ORDER BY COALESCE(last_seen,first_seen) DESC LIMIT 1},undef,$qid) if $self->{has_display_queue_id};
    return if !$m;
    my $internal=$m->{queue_id};
    $m->{recipients}=$self->{dbh}->selectall_arrayref('SELECT recipient,status,dsn,relay,timestamp FROM recipients WHERE queue_id=? ORDER BY id',{Slice=>{}},$internal);
    my $rows=$self->{dbh}->selectall_arrayref('SELECT timestamp,source,type,data_json,raw FROM events WHERE queue_id=? ORDER BY id',{Slice=>{}},$internal); for (@$rows) { $_->{data}=eval{decode_json($_->{data_json})}||{}; delete $_->{data_json}; } $m->{events}=$rows; return $m;
}
sub daily_series {
    my ($self,$days)=@_; $days||=30;
    return $self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,1,10) day, COUNT(*) messages, SUM(delivered_count) delivered, SUM(rejected) rejected, SUM(spam_detected) spam_detected FROM messages WHERE first_seen >= datetime('now', ?) GROUP BY day ORDER BY day},{Slice=>{}},'-'.$days.' days');
}
sub hourly_series {
    my ($self,$date)=@_; $date||='';
    my ($from,$to);
    if ($date =~ /^\d{4}-\d{2}-\d{2}$/) { $from=$date.'T00:00:00'; $to=$date.'T23:59:59.999999'; }
    else { my ($d)=$self->{dbh}->selectrow_array(q{SELECT date('now','localtime')}); $date=$d; $from=$date.'T00:00:00'; $to=$date.'T23:59:59.999999'; }
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,12,2) hour, COUNT(*) messages, SUM(delivered_count) delivered, SUM(rejected) rejected, SUM(spam_detected) spam_detected, COALESCE(SUM(size),0) size_bytes FROM messages WHERE first_seen >= ? AND first_seen <= ? GROUP BY hour ORDER BY hour},{Slice=>{}},$from,$to);
    my %by=map { (defined($_->{hour})?$_->{hour}:'') => $_ } @$rows;
    for my $a (@{$self->_legacy_agg_by_hour('delivery_sent',$date)}) { $by{$a->{hour}}{delivered}=0+($by{$a->{hour}}{delivered}||0)+$a->{count}; }
    for my $a (@{$self->_legacy_agg_by_hour('spam_detected',$date)}) { $by{$a->{hour}}{spam_detected}=0+($by{$a->{hour}}{spam_detected}||0)+$a->{count}; }
    my @out;
    for my $h (0..23) { my $k=sprintf('%02d',$h); push @out, $by{$k} || {hour=>$k,messages=>0,delivered=>0,rejected=>0,spam_detected=>0,size_bytes=>0}; }
    return \@out;
}
sub hourly_flow_series {
    my ($self,$date)=@_; $date||='';
    my ($from,$to);
    if ($date =~ /^\d{4}-\d{2}-\d{2}$/) { $from=$date.'T00:00:00'; $to=$date.'T23:59:59.999999'; }
    else { my ($d)=$self->{dbh}->selectrow_array(q{SELECT date('now','localtime')}); $date=$d; $from=$date.'T00:00:00'; $to=$date.'T23:59:59.999999'; }
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,12,2) hour,
      SUM(CASE WHEN direction='inbound' THEN 1 ELSE 0 END) inbound,
      SUM(CASE WHEN direction='outbound' THEN 1 ELSE 0 END) outbound,
      SUM(CASE WHEN direction='internal' THEN 1 ELSE 0 END) internal,
      SUM(CASE WHEN direction='relay' THEN 1 ELSE 0 END) relay,
      SUM(CASE WHEN direction IS NULL OR direction='' OR direction='unknown' THEN 1 ELSE 0 END) unknown,
      COALESCE(SUM(CASE WHEN direction='inbound' THEN size ELSE 0 END),0) inbound_bytes,
      COALESCE(SUM(CASE WHEN direction='outbound' THEN size ELSE 0 END),0) outbound_bytes,
      COALESCE(SUM(CASE WHEN direction='internal' THEN size ELSE 0 END),0) internal_bytes,
      COALESCE(SUM(CASE WHEN direction='relay' THEN size ELSE 0 END),0) relay_bytes,
      COALESCE(SUM(CASE WHEN direction IS NULL OR direction='' OR direction='unknown' THEN size ELSE 0 END),0) unknown_bytes
      FROM messages WHERE first_seen >= ? AND first_seen <= ? GROUP BY hour ORDER BY hour},{Slice=>{}},$from,$to);
    my %by=map { (defined($_->{hour})?$_->{hour}:'') => $_ } @$rows; my @out;
    for my $h (0..23) { my $k=sprintf('%02d',$h); push @out, $by{$k} || {hour=>$k,inbound=>0,outbound=>0,internal=>0,relay=>0,unknown=>0,inbound_bytes=>0,outbound_bytes=>0,internal_bytes=>0,relay_bytes=>0,unknown_bytes=>0}; }
    return \@out;
}
sub month_daily_flow_series {
    my ($self,$month)=@_; return [] if !defined($month) || $month !~ /^(\d{4})-(\d{2})$/;
    my ($y,$m)=($1,0+$2); my ($ny,$nm)=($y,$m+1); if($nm==13){$ny++;$nm=1}
    my $from=sprintf('%04d-%02d-01T00:00:00',$y,$m); my $to=sprintf('%04d-%02d-01T00:00:00',$ny,$nm);
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,1,10) day,
      SUM(CASE WHEN direction='inbound' THEN 1 ELSE 0 END) inbound,
      SUM(CASE WHEN direction='outbound' THEN 1 ELSE 0 END) outbound,
      SUM(CASE WHEN direction='internal' THEN 1 ELSE 0 END) internal,
      SUM(CASE WHEN direction='relay' THEN 1 ELSE 0 END) relay,
      SUM(CASE WHEN direction IS NULL OR direction='' OR direction='unknown' THEN 1 ELSE 0 END) unknown,
      COALESCE(SUM(CASE WHEN direction='inbound' THEN size ELSE 0 END),0) inbound_bytes,
      COALESCE(SUM(CASE WHEN direction='outbound' THEN size ELSE 0 END),0) outbound_bytes,
      COALESCE(SUM(CASE WHEN direction='internal' THEN size ELSE 0 END),0) internal_bytes,
      COALESCE(SUM(CASE WHEN direction='relay' THEN size ELSE 0 END),0) relay_bytes,
      COALESCE(SUM(CASE WHEN direction IS NULL OR direction='' OR direction='unknown' THEN size ELSE 0 END),0) unknown_bytes
      FROM messages WHERE first_seen >= ? AND first_seen < ? GROUP BY day ORDER BY day},{Slice=>{}},$from,$to);
    my %by=map { $_->{day} => $_ } @$rows; my @out;
    my $leap=($y%4==0 && ($y%100!=0 || $y%400==0))?1:0;
    my @dims=(31,$leap?29:28,31,30,31,30,31,31,30,31,30,31); my $dim=$dims[$m-1];
    for my $d (1..$dim){ my $day=sprintf('%04d-%02d-%02d',$y,$m,$d); push @out,$by{$day} || {day=>$day,inbound=>0,outbound=>0,internal=>0,relay=>0,unknown=>0,inbound_bytes=>0,outbound_bytes=>0,internal_bytes=>0,relay_bytes=>0,unknown_bytes=>0}; }
    return \@out;
}
sub unique_party_counts {
    my ($self,$from,$to)=@_;
    my (@w,@b);
    if (defined($from) && $from ne '') { push @w,'m.first_seen >= ?'; push @b,$from; }
    if (defined($to) && $to ne '') { push @w,'m.first_seen <= ?'; push @b,$to; }
    my $where=@w?'WHERE '.join(' AND ',@w):'';
    my $senders=$self->{dbh}->selectrow_array("SELECT COUNT(DISTINCT NULLIF(m.sender,'')) FROM messages m $where",undef,@b);
    my $recipients=$self->{dbh}->selectrow_array("SELECT COUNT(DISTINCT NULLIF(r.recipient,'')) FROM recipients r JOIN messages m ON m.queue_id=r.queue_id $where",undef,@b);
    return {senders=>0+($senders||0),recipients=>0+($recipients||0)};
}
sub month_daily_series {
    my ($self,$month)=@_;
    return [] if !defined($month) || $month !~ /^(\d{4})-(\d{2})$/;
    my ($y,$m)=($1,0+$2); my ($ny,$nm)=($y,$m+1); if($nm==13){$ny++;$nm=1}
    my $from=sprintf('%04d-%02d-01T00:00:00',$y,$m); my $to=sprintf('%04d-%02d-01T00:00:00',$ny,$nm);
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,1,10) day, COUNT(*) messages, SUM(delivered_count) delivered, SUM(rejected) rejected, SUM(spam_detected) spam_detected FROM messages WHERE first_seen >= ? AND first_seen < ? GROUP BY day ORDER BY day},{Slice=>{}},$from,$to);
    my %by=map { $_->{day} => $_ } @$rows; my $last=sprintf('%04d-%02d-31',$y,$m);
    for my $a (@{$self->_legacy_agg_by_day('delivery_sent',substr($from,0,10),$last)}) { $by{$a->{day}}{day}=$a->{day}; $by{$a->{day}}{delivered}=0+($by{$a->{day}}{delivered}||0)+$a->{count}; }
    for my $a (@{$self->_legacy_agg_by_day('spam_detected',substr($from,0,10),$last)}) { $by{$a->{day}}{day}=$a->{day}; $by{$a->{day}}{spam_detected}=0+($by{$a->{day}}{spam_detected}||0)+$a->{count}; }
    return [map { my $r=$by{$_}; $r->{messages}=0+($r->{messages}||0); $r->{delivered}=0+($r->{delivered}||0); $r->{rejected}=0+($r->{rejected}||0); $r->{spam_detected}=0+($r->{spam_detected}||0); $r } sort keys %by];
}
sub flow_summary {
    my ($self,$from,$to)=@_;
    my (@w,@b);
    if (defined($from) && $from ne '') { push @w,'first_seen >= ?'; push @b,$from; }
    if (defined($to) && $to ne '') { push @w,'first_seen <= ?'; push @b,$to; }
    my $where=@w?'WHERE '.join(' AND ',@w):'';
    return $self->{dbh}->selectall_arrayref("SELECT COALESCE(direction,'unknown') direction, COUNT(*) messages, COALESCE(SUM(size),0) bytes, COALESCE(AVG(size),0) avg_bytes, COALESCE(SUM(delivered_count),0) delivered FROM messages $where GROUP BY direction ORDER BY messages DESC",{Slice=>{}},@b);
}
sub monthly_series {
    my ($self,$months)=@_; $months||=12; $months=24 if $months>24;
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,1,7) month, COUNT(*) messages, SUM(delivered_count) delivered, SUM(rejected) rejected, SUM(spam_detected) spam_detected FROM messages WHERE first_seen >= date('now','start of month', ?) GROUP BY month ORDER BY month},{Slice=>{}},'-'.($months-1).' months');
    my %by=map { $_->{month}=>$_ } @$rows;
    my $agg=$self->{dbh}->selectall_arrayref(q{SELECT substr(day,1,7) month, metric, SUM(count) count FROM legacy_aggregates WHERE day >= date('now','start of month', ?) AND metric IN ('delivery_sent','spam_detected') GROUP BY month,metric},{Slice=>{}},'-'.($months-1).' months');
    for my $a (@$agg) { my $r=($by{$a->{month}} ||= {month=>$a->{month},messages=>0,delivered=>0,rejected=>0,spam_detected=>0}); $r->{delivered}+=$a->{count} if $a->{metric} eq 'delivery_sent'; $r->{spam_detected}+=$a->{count} if $a->{metric} eq 'spam_detected'; }
    return [map {$by{$_}} sort keys %by];
}
sub spam_daily_series {
    my ($self,$days)=@_; $days||=30;
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT substr(first_seen,1,10) day, SUM(spam_detected) detected, SUM(spam_rejected) rejected, SUM(spam_delivered) delivered FROM messages WHERE first_seen >= datetime('now', ?) GROUP BY day ORDER BY day},{Slice=>{}},'-'.$days.' days');
    my %by=map { $_->{day}=>$_ } @$rows;
    my ($from)=$self->{dbh}->selectrow_array(q{SELECT date('now', ?)},undef,'-'.$days.' days');
    for my $metric (qw(spam_detected spam_rejected)) {
        for my $a (@{$self->_legacy_agg_by_day($metric,$from,undef)}) {
            my $r=($by{$a->{day}} ||= {day=>$a->{day},detected=>0,rejected=>0,delivered=>0});
            $r->{detected}+=$a->{count} if $metric eq 'spam_detected';
            $r->{rejected}+=$a->{count} if $metric eq 'spam_rejected';
        }
    }
    return [map {$by{$_}} sort keys %by];
}
sub top_senders {
    my ($self,$limit,$from,$to)=@_; $limit||=20; my(@w,@b); if($from){push @w,'first_seen >= ?';push @b,$from} if($to){push @w,'first_seen <= ?';push @b,$to} my $where=@w?'WHERE '.join(' AND ',@w):'';
    return $self->{dbh}->selectall_arrayref("SELECT COALESCE(NULLIF(sender,''),'Sender unavailable in historical data') sender, COUNT(*) count, SUM(delivered_count) delivered, SUM(spam_detected) spam FROM messages $where GROUP BY sender ORDER BY count DESC LIMIT ?",{Slice=>{}},@b,$limit);
}
sub top_recipients {
    my ($self,$limit,$from,$to)=@_; $limit||=20; my(@w,@b); if($from){push @w,'m.first_seen >= ?';push @b,$from} if($to){push @w,'m.first_seen <= ?';push @b,$to} my $where=@w?'WHERE '.join(' AND ',@w):'';
    return $self->{dbh}->selectall_arrayref("SELECT COALESCE(NULLIF(r.recipient,''),'(empty)') recipient, COUNT(*) count, SUM(CASE WHEN lower(COALESCE(r.status,''))='sent' THEN 1 ELSE 0 END) sent FROM recipients r JOIN messages m ON m.queue_id=r.queue_id $where GROUP BY r.recipient ORDER BY count DESC LIMIT ?",{Slice=>{}},@b,$limit);
}
sub top_reject_reasons {
    my ($self,$limit)=@_; $limit||=20; my %x;
    my $rows=$self->{dbh}->selectall_arrayref(q{SELECT type, COALESCE(json_extract(data_json,'$.reason'),'(no detail)') reason, COUNT(*) count FROM events WHERE type IN ('smtp_reject','dnsbl_reject','milter_reject') GROUP BY type,reason},{Slice=>{}});
    for my $r (@$rows) { $x{join("\0",$r->{type},$r->{reason})}+=$r->{count}; }
    my $legacy_rows=$self->{dbh}->selectall_arrayref(q{SELECT detail reason,SUM(count) count FROM legacy_aggregates WHERE metric='smtp_rejected' GROUP BY detail},{Slice=>{}});
    for my $r (@$legacy_rows) { my $reason=$r->{reason} ne ''?$r->{reason}:'(no detail)'; $x{join("\0",'smtp_reject',$reason)}+=$r->{count}; }
    my @out=map { my($type,$reason)=split /\0/,$_,2; {type=>$type,reason=>$reason,count=>$x{$_}} } keys %x;
    @out=sort { $b->{count}<=>$a->{count} || $a->{type} cmp $b->{type} || $a->{reason} cmp $b->{reason} } @out;
    splice(@out,$limit) if @out>$limit; return \@out;
}
sub engine_stats {
    my ($self)=@_; return {
      rspamd => $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(rspamd_action,'(no action)') action, COUNT(*) count FROM messages WHERE rspamd_action IS NOT NULL GROUP BY rspamd_action ORDER BY count DESC},{Slice=>{}}),
      dkim => $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(dkim_result,'none') result, COUNT(*) count FROM messages GROUP BY dkim_result ORDER BY count DESC},{Slice=>{}}),
      dmarc => $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(dmarc_result,'none') result, COUNT(*) count FROM messages GROUP BY dmarc_result ORDER BY count DESC},{Slice=>{}}),
    };
}

sub rspamd_native_stats {
    my ($self)=@_;
    return {
      settings => $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(json_extract(data_json,'$.settings_id'),'(default)') settings_id, COUNT(*) count FROM events WHERE source='rspamd' AND type='verdict' AND json_extract(data_json,'$.evidence')='rspamd.log' GROUP BY settings_id ORDER BY count DESC},{Slice=>{}}),
      forced => $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(json_extract(data_json,'$.forced_action'),'(none)') forced_action, COUNT(*) count FROM events WHERE source='rspamd' AND type='verdict' AND json_extract(data_json,'$.evidence')='rspamd.log' GROUP BY forced_action ORDER BY count DESC},{Slice=>{}}),
      scans => 0 + ($self->{dbh}->selectrow_array(q{SELECT COUNT(*) FROM events WHERE source='rspamd' AND type='verdict' AND json_extract(data_json,'$.evidence')='rspamd.log'})||0),
    };
}

sub auth_stats {
    my ($self)=@_;
    return $self->{dbh}->selectall_arrayref(q{SELECT source, COALESCE(protocol,'') protocol, COALESCE(method,'') method, success, COUNT(*) count FROM auth_events GROUP BY source,protocol,method,success ORDER BY count DESC},{Slice=>{}});
}
sub tls_stats {
    my ($self)=@_;
    return $self->{dbh}->selectall_arrayref(q{SELECT COALESCE(direction,'unknown') direction, COALESCE(protocol,'unknown') protocol, COUNT(*) count FROM tls_events GROUP BY direction,protocol ORDER BY count DESC},{Slice=>{}});
}
sub dsn_stats {
    my ($self)=@_; my %x;
    for my $r (@{$self->{dbh}->selectall_arrayref(q{SELECT COALESCE(json_extract(data_json,'$.status'),'unknown') status, COUNT(*) count FROM events WHERE type='dsn' GROUP BY status},{Slice=>{}})}) { $x{$r->{status}}+=$r->{count}; }
    for my $r (@{$self->{dbh}->selectall_arrayref(q{SELECT COALESCE(NULLIF(detail,''),'unknown') status,SUM(count) count FROM legacy_aggregates WHERE metric='dsn_events' GROUP BY status},{Slice=>{}})}) { $x{$r->{status}}+=$r->{count}; }
    return [sort {$b->{count}<=>$a->{count}} map {{status=>$_,count=>$x{$_}}} keys %x];
}
sub top_viruses {
    my ($self,$limit)=@_; $limit||=20; my %x;
    for my $r (@{$self->{dbh}->selectall_arrayref(q{SELECT COALESCE(NULLIF(virus_name,''),COALESCE(NULLIF(av_status,''),'unknown')) virus, COUNT(*) count FROM messages WHERE lower(COALESCE(av_status,'')) NOT IN ('','clean','ok') GROUP BY virus},{Slice=>{}})}) { $x{$r->{virus}}+=$r->{count}; }
    for my $r (@{$self->{dbh}->selectall_arrayref(q{SELECT COALESCE(NULLIF(detail,''),'unknown') virus,SUM(count) count FROM legacy_aggregates WHERE metric='virus_detected' GROUP BY virus},{Slice=>{}})}) { $x{$r->{virus}}+=$r->{count}; }
    my @out=sort {$b->{count}<=>$a->{count}} map {{virus=>$_,count=>$x{$_}}} keys %x; splice(@out,$limit) if @out>$limit; return \@out;
}
sub prune_raw_events {
    my ($self,$days)=@_; return 0 if !$days || $days<1;
    # Retention applies only to the literal log line. Structured event data
    # remains available for historical statistics, correlation and audits.
    $self->{dbh}->do(q{UPDATE events SET raw=NULL WHERE raw IS NOT NULL AND timestamp < datetime('now', ?)},undef,'-'.$days.' days');
    return $self->_changes;
}
1;
