package SendmailAnalyzer::LegacyIdentity;
use strict;
use warnings;
use Digest::SHA qw(sha1_hex);

sub new {
    my ($class,%opt)=@_;
    my $source=$opt{source} or die 'source required';
    my $self=bless {
        source=>$source,
        storage=>$opt{storage},
        until=>$opt{until},
        map=>{},
        reused=>0,
        synthetic=>0,
        existing_conflicts=>0,
    },$class;
    $self->_build;
    return $self;
}

sub _existing_date {
    my ($self,$qid)=@_;
    my $st=$self->{storage};
    return undef if !$st || !$st->can('dbh');
    my $dbh=eval { $st->dbh } or return undef;
    my ($first)=eval { $dbh->selectrow_array('SELECT first_seen FROM messages WHERE queue_id=?',undef,$qid) };
    return undef if !defined($first) || $first eq '';
    return substr($first,0,10);
}

sub _synthetic {
    my ($qid,$host,$date)=@_;
    my $tag=substr(sha1_hex(join("\0",$host||'', $date||'', $qid||'')),0,12);
    my $d=$date||'0000-00-00'; $d=~s/[^0-9]//g;
    return $qid.'__L'.$d.'_'.$tag;
}

sub _build {
    my ($self)=@_;
    my %loc;
    my %args=defined($self->{until}) ? (until=>$self->{until}) : ();
    for my $entry (@{$self->{source}->entries(type=>'senders',%args)}) {
        my $where=join('/',@{$entry}{qw(host date)});
        my $fh=$self->{source}->open_entry($entry);
        while (my $line=<$fh>) {
            next if $line !~ /\S/;
            my (undef,$qid)=split /:/,$line,3;
            next if !defined($qid) || $qid eq '' || $qid =~ /^(?:FaKe|NOQUEUE$)/;
            $loc{$qid}{$where}=1;
        }
        $self->{source}->close_entry($fh,$entry);
    }
    for my $qid (sort keys %loc) {
        my @where=sort keys %{$loc{$qid}};
        my $existing=$self->_existing_date($qid);
        $self->{reused}++ if @where>1;
        for my $where (@where) {
            my ($host,$date)=split m{/},$where,2;
            my $keep_original=0;
            if (@where==1) {
                $keep_original=1 if !defined($existing) || $existing eq $date;
            } elsif (defined($existing)) {
                $keep_original=1 if $existing eq $date;
            } else {
                # No native row exists yet. Keep one deterministic generation on
                # the historical Queue-ID and qualify the other generations.
                $keep_original=1 if $where eq $where[0];
            }
            if (!$keep_original) {
                $self->{map}{join('/', $host,$date,$qid)}=_synthetic($qid,$host,$date);
                $self->{synthetic}++;
                $self->{existing_conflicts}++ if defined($existing) && $existing ne $date;
            }
        }
    }
}

sub internal_qid {
    my ($self,$host,$date,$qid)=@_;
    return $qid if !defined($qid) || $qid eq '';
    return $self->{map}{join('/', $host||'', $date||'', $qid)} || $qid;
}
sub reused_queue_ids { shift->{reused} }
sub synthetic_generations { shift->{synthetic} }
sub existing_conflicts { shift->{existing_conflicts} }

1;
