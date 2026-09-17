package SendmailAnalyzer::MigrationAudit;
use strict;
use warnings;
use SendmailAnalyzer::LegacySource;

sub _entry_lines {
    my ($source,$entry,$filter)=@_; return 0 if !$entry;
    my $fh=$source->open_entry($entry); my $n=0;
    while (my $line=<$fh>) { next if $filter && $line !~ $filter; $n++ if $line =~ /\S/; }
    $source->close_entry($fh,$entry); return $n;
}

sub _file_lines {
    my ($file,$filter)=@_; return 0 if !-f $file;
    open my $fh,'<',$file or return 0; my $n=0;
    while (my $line=<$fh>) { next if $filter && $line !~ $filter; $n++ if $line =~ /\S/; }
    close $fh; return $n;
}
sub _real_sender_entry_lines {
    my ($source,$entry)=@_; return 0 if !$entry;
    my $fh=$source->open_entry($entry); my $n=0;
    while (my $line=<$fh>) { next if $line !~ /\S/; my (undef,$qid)=split /:/,$line,3; $n++ if defined($qid) && $qid ne '' && $qid !~ /^(?:FaKe|NOQUEUE$)/; }
    $source->close_entry($fh,$entry); return $n;
}
sub _real_sender_file_lines {
    my ($file)=@_; return 0 if !-f $file; open my $fh,'<',$file or return 0; my $n=0;
    while (my $line=<$fh>) { next if $line !~ /\S/; my (undef,$qid)=split /:/,$line,3; $n++ if defined($qid) && $qid ne '' && $qid !~ /^(?:FaKe|NOQUEUE$)/; }
    close $fh; return $n;
}

sub duplicate_lines {
    my ($class,$file)=@_; return 0 if !-f $file;
    open my $fh,'<',$file or return 0; my (%seen,$total);
    while (my $line=<$fh>) { chomp $line; next if $line !~ /\S/; $total++; $seen{$line}++; }
    close $fh; return $total-scalar(keys %seen);
}

sub _duplicate_entry_lines {
    my ($source,$entry)=@_; return 0 if !$entry;
    my $fh=$source->open_entry($entry); my (%seen,$total);
    while (my $line=<$fh>) { chomp $line; next if $line !~ /\S/; $total++; $seen{$line}++; }
    $source->close_entry($fh,$entry); return $total-scalar(keys %seen);
}

sub discover_days {
    my ($class,$root)=@_;
    my $source=SendmailAnalyzer::LegacySource->new(root=>$root);
    my $days=$source->day_map();
    $_->{source}=$source for @$days;
    return $days;
}

sub legacy_counts {
    my ($class,$day)=@_;
    # Backwards-compatible direct-directory API used by older callers/tests.
    if (!ref($day)) {
        return {
          messages   => _real_sender_file_lines("$day/senders.dat"),
          recipients => _file_lines("$day/recipient.dat"),
          sent       => _file_lines("$day/recipient.dat",qr/:Sent\s*$/i),
          spam       => _file_lines("$day/spam.dat"),
          virus      => _file_lines("$day/virus.dat"),
          dsn        => _file_lines("$day/dsn.dat"),
          auth       => _file_lines("$day/auth.dat"),
          rejected   => _file_lines("$day/rejected.dat"),
        };
    }
    my $source=$day->{source} or die 'legacy day source missing'; my $e=$day->{entries}||{};
    return {
      messages   => _real_sender_entry_lines($source,$e->{senders}),
      recipients => _entry_lines($source,$e->{recipient}),
      sent       => _entry_lines($source,$e->{recipient},qr/:Sent\s*$/i),
      spam       => _entry_lines($source,$e->{spam}),
      virus      => _entry_lines($source,$e->{virus}),
      dsn        => _entry_lines($source,$e->{dsn}),
      auth       => _entry_lines($source,$e->{auth}),
      rejected   => _entry_lines($source,$e->{rejected}),
    };
}

sub sqlite_counts {
    my ($class,$dbh,$date,$exact_legacy)=@_; my $like="$date%";
    if ($exact_legacy) {
        my $agg=sub { my($metric)=@_; return 0 if !$dbh->selectrow_array("SELECT 1 FROM sqlite_master WHERE type='table' AND name='legacy_aggregates'"); my($n)=$dbh->selectrow_array('SELECT COALESCE(SUM(count),0) FROM legacy_aggregates WHERE day=? AND metric=?',undef,$date,$metric); return 0+($n||0); };
        return {
          messages   => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='envelope'",undef,$like),
          recipients => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='delivery'",undef,$like)+$agg->('recipient'),
          sent       => 0+$dbh->selectrow_array(q{SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='delivery' AND lower(COALESCE(json_extract(data_json,'$.status'),''))='sent'},undef,$like)+$agg->('delivery_sent'),
          spam       => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='spam'",undef,$like)+$agg->('spam_detected'),
          virus      => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='virus_verdict'",undef,$like)+$agg->('virus_detected'),
          dsn        => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type='dsn'",undef,$like)+$agg->('dsn_events'),
          auth       => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type IN ('smtp_auth','tls')",undef,$like),
          rejected   => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND source='legacy' AND type IN ('smtp_reject','dnsbl_reject')",undef,$like)+$agg->('smtp_rejected'),
        };
    }
    return {
      messages   => 0+$dbh->selectrow_array('SELECT COUNT(*) FROM messages WHERE first_seen LIKE ?',undef,$like),
      recipients => 0+$dbh->selectrow_array('SELECT COUNT(*) FROM recipients WHERE timestamp LIKE ?',undef,$like),
      sent       => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM recipients WHERE timestamp LIKE ? AND lower(COALESCE(status,''))='sent'",undef,$like),
      spam       => 0+$dbh->selectrow_array('SELECT COUNT(*) FROM messages WHERE first_seen LIKE ? AND spam_detected=1',undef,$like),
      virus      => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND type='virus_verdict'",undef,$like),
      dsn        => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND type='dsn'",undef,$like),
      auth       => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND type IN ('smtp_auth','tls')",undef,$like),
      rejected   => 0+$dbh->selectrow_array("SELECT COUNT(*) FROM events WHERE timestamp LIKE ? AND type IN ('smtp_reject','dnsbl_reject')",undef,$like),
    };
}

sub audit {
    my ($class,%opt)=@_; my $root=$opt{root} or die 'root required'; my $dbh=$opt{dbh} or die 'dbh required';
    my $exact=$opt{exact_through}; my $days=$class->discover_days($root);
    my @hard=qw(messages recipients sent spam virus dsn auth rejected);
    my %total_delta; my @rows; my $exact_days=0; my $exact_mismatches=0;
    for my $d (@$days) {
        next if !exists($d->{entries}{senders});
        my $is_exact=defined($exact) && $d->{date} le $exact ? 1:0;
        my $v9=$class->legacy_counts($d); my $v10=$class->sqlite_counts($dbh,$d->{date},$is_exact);
        my %delta=map { $_ => $v10->{$_}-$v9->{$_} } keys %$v9;
        $total_delta{$_}+=$delta{$_} for keys %delta;
        my @bad=$is_exact ? grep { $delta{$_} != 0 } @hard : ();
        $exact_days++ if $is_exact; $exact_mismatches+=@bad;
        my $auth_dup=_duplicate_entry_lines($d->{source},$d->{entries}{auth});
        push @rows,{host=>$d->{host},date=>$d->{date},v9=>$v9,v10=>$v10,delta=>\%delta,exact=>$is_exact,bad=>\@bad,auth_duplicate_lines=>$auth_dup};
    }
    return {days=>scalar(grep { exists($_->{entries}{senders}) } @$days),exact_days=>$exact_days,exact_mismatches=>$exact_mismatches,total_delta=>\%total_delta,rows=>\@rows};
}
1;
