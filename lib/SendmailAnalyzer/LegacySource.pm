package SendmailAnalyzer::LegacySource;
use strict;
use warnings;
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use Digest::SHA qw(sha1_hex);

sub new {
    my ($class,%opt)=@_;
    my $root=$opt{root} || die 'root required';
    $root =~ s{/+$}{};
    return bless {root=>$root, entries=>undef, archives=>0, archived_entries=>0, archive_cache=>{}, progress=>$opt{progress}},$class;
}

sub root { shift->{root} }
sub archives { my ($self)=@_; $self->_scan if !defined $self->{entries}; return $self->{archives}; }
sub archived_entries { my ($self)=@_; $self->_scan if !defined $self->{entries}; return $self->{archived_entries}; }
sub archive_extractions { my ($self)=@_; return 0+($self->{archive_extractions}||0); }

sub _safe_member_name {
    my ($member)=@_;
    return if !defined($member) || $member eq '' || $member =~ /\0/;
    return if $member =~ m{^/};
    my $n=$member; $n =~ s{^\./+}{}; $n =~ s{/+}{/}g;
    return if $n eq '' || $n =~ m{(?:^|/)\.\.(?:/|$)};
    return $n;
}

sub _progress {
    my ($self,$msg)=@_;
    my $cb=$self->{progress};
    $cb->($msg) if $cb && ref($cb) eq 'CODE';
}

sub _archive_members {
    my ($archive)=@_;
    open my $fh,'-|','tar','-tzf',$archive or die "cannot list $archive: $!\n";
    my @m;
    while (my $line=<$fh>) { chomp $line; push @m,$line if $line ne ''; }
    close $fh or die "cannot read tar index $archive\n";
    return @m;
}

sub _member_meta {
    my ($member,$host,$y,$m)=@_;
    my $n=_safe_member_name($member); return if !defined $n;
    # Preferred: archive contains the complete legacy path or host/year/month/day.
    if ($n =~ m{(?:^|/)\Q$host\E/\Q$y\E/\Q$m\E/(\d{2})/([^/]+)\.dat$}) {
        return ($1,$2);
    }
    if ($n =~ m{(?:^|/)\Q$y\E/\Q$m\E/(\d{2})/([^/]+)\.dat$}) {
        return ($1,$2);
    }
    # Upstream FREE_SPACE=archive commonly stores day directories relative to the month.
    if ($n =~ m{(?:^|/)(\d{2})/([^/]+)\.dat$}) {
        return ($1,$2);
    }
    return;
}

sub _scan {
    my ($self)=@_;
    my $root=$self->{root}; my %by_key; my @archives;
    if (-d $root) {
        find(sub {
            my $p=$File::Find::name;
            if (-f $_ && $_ =~ /\.dat$/ && $p =~ m{^\Q$root\E/([^/]+)/(\d{4})/(\d{2})/(\d{2})/([^/]+)\.dat$}) {
                my ($host,$y,$m,$d,$type)=($1,$2,$3,$4,$5);
                my $key=join('/', $host,$y,$m,$d,$type);
                $by_key{$key}={kind=>'file',path=>$p,host=>$host,year=>$y,month=>$m,day=>$d,date=>"$y-$m-$d",type=>$type,key=>$key,locator=>join('/', $host,$y,$m,$d,$type.'.dat')};
            } elsif (-f $_ && $_ eq 'history.tar.gz' && $p =~ m{^\Q$root\E/([^/]+)/(\d{4})/(\d{2})/history\.tar\.gz$}) {
                push @archives,[$p,$1,$2,$3];
            }
        },$root);
    }
    my $archived=0;
    for my $a (sort {$a->[0] cmp $b->[0]} @archives) {
        my ($archive,$host,$y,$m)=@$a;
        for my $member (_archive_members($archive)) {
            my ($d,$type)=_member_meta($member,$host,$y,$m); next if !defined $d;
            next if $d !~ /^(?:0[1-9]|[12]\d|3[01])$/;
            my $key=join('/', $host,$y,$m,$d,$type);
            next if exists $by_key{$key}; # active .dat is authoritative if both exist
            $by_key{$key}={kind=>'archive',archive=>$archive,member=>$member,host=>$host,year=>$y,month=>$m,day=>$d,date=>"$y-$m-$d",type=>$type,key=>$key,locator=>join('/', $host,$y,$m,$d,$type.'.dat')};
            $archived++;
        }
    }
    # Process senders.dat first within each host/day so it establishes the
    # canonical set of real Postfix Queue-IDs before recipient/reject/spam
    # side-data tries to enrich a message.  This prevents 9.4 synthetic
    # FaKe* identifiers used for NOQUEUE rejects from becoming messages.
    my @entries=sort {
        $a->{date} cmp $b->{date} || $a->{host} cmp $b->{host} ||
        (($a->{type} eq 'senders') ? 0 : 1) <=> (($b->{type} eq 'senders') ? 0 : 1) ||
        $a->{type} cmp $b->{type}
    } values %by_key;
    my %selected;
    for my $e (@entries) { push @{$selected{$e->{archive}}},$e->{member} if ($e->{kind}||'') eq 'archive'; }
    my %archive_no; my $n=0;
    for my $a (sort keys %selected) { $archive_no{$a}=++$n; }
    $self->{selected_archive_members}=\%selected;
    $self->{archive_number}=\%archive_no;
    $self->{entries}=\@entries; $self->{archives}=0+@archives; $self->{archived_entries}=$archived;
    return $self->{entries};
}

sub entries {
    my ($self,%opt)=@_;
    my $all=$self->_scan if !defined $self->{entries}; $all=$self->{entries} if defined $self->{entries};
    my @r=@$all;
    @r=grep { $_->{type} eq $opt{type} } @r if defined $opt{type};
    @r=grep { $_->{date} le $opt{until} } @r if defined $opt{until};
    for my $e (@r) { $self->{requested_archive_members}{$e->{archive}}{$e->{member}}=1 if ($e->{kind}||'') eq 'archive'; }
    return \@r;
}

sub _prepare_archive {
    my ($self,$archive)=@_;
    $self->_scan if !defined $self->{entries};
    my @members=sort keys %{$self->{requested_archive_members}{$archive}||{}};
    @members=@{$self->{selected_archive_members}{$archive}||[]} if !@members;
    die "archive not indexed: $archive\n" if !@members;
    my $existing=$self->{archive_cache}{$archive}||{};
    my @missing=grep { !exists $existing->{$_} } @members;
    return $existing if !@missing;
    @members=@missing;

    my $tmp=$self->{archive_tmp_root};
    if (!$tmp) {
        $tmp=tempdir('sendmailanalyzer-legacy-XXXXXX',TMPDIR=>1,CLEANUP=>1);
        chmod 0700,$tmp;
        $self->{archive_tmp_root}=$tmp;
    }
    my $dest=$self->{archive_cache_dir}{$archive} || "$tmp/".sha1_hex($archive);
    make_path($dest,{mode=>0700});
    $self->{archive_cache_dir}{$archive}=$dest;
    my $list="$tmp/members-".sha1_hex($archive).'.nul';
    open my $lf,'>:raw',$list or die "cannot create archive member list $list: $!\n";
    my %safe;
    for my $member (@members) {
        my $rel=_safe_member_name($member);
        die "unsafe path in legacy archive $archive: $member\n" if !defined $rel;
        $safe{$member}=$rel;
        print {$lf} $member,"\0";
    }
    close $lf or die "cannot close archive member list $list: $!\n";
    my $num=$self->{archive_number}{$archive}||1;
    my $total=scalar(keys %{$self->{selected_archive_members}||{}})||1;
    $self->_progress("Legacy archive $num/$total: extracting selected data once (".scalar(@members)." files) from $archive");
    system('tar','-xzf',$archive,'-C',$dest,'--no-same-owner','--no-same-permissions','--null','--verbatim-files-from','-T',$list)==0
        or die "cannot extract selected legacy data from $archive\n";
    unlink $list;
    my %paths;
    for my $member (@members) {
        my $path="$dest/$safe{$member}";
        my @st=lstat($path);
        die "archive member was not extracted as a regular file: $archive:$member\n" if !@st || -l _ || !-f _;
        $paths{$member}=$path;
    }
    $self->{archive_cache}{$archive} ||= {};
    @{$self->{archive_cache}{$archive}}{keys %paths}=values %paths;
    $self->{archive_extractions}=1+($self->{archive_extractions}||0);
    return $self->{archive_cache}{$archive};
}

sub prepare_entries {
    my ($self,$entries)=@_;
    my %archives;
    for my $e (@{$entries||[]}) { $archives{$e->{archive}}=1 if ($e->{kind}||'') eq 'archive'; }
    $self->_prepare_archive($_) for sort keys %archives;
    return scalar keys %archives;
}

sub open_entry {
    my ($self,$e)=@_;
    die 'entry required' if ref($e) ne 'HASH';
    if (($e->{kind}||'') eq 'file') {
        open my $fh,'<',$e->{path} or die "cannot open $e->{path}: $!\n";
        return $fh;
    }
    if (($e->{kind}||'') eq 'archive') {
        $self->{requested_archive_members}{$e->{archive}}{$e->{member}}=1;
        my $cache=$self->_prepare_archive($e->{archive});
        my $path=$cache->{$e->{member}} or die "archive member not staged: $e->{archive}:$e->{member}\n";
        open my $fh,'<',$path or die "cannot open staged legacy data $path: $!\n";
        return $fh;
    }
    die 'unknown legacy entry kind';
}

sub close_entry {
    my ($self,$fh,$e)=@_;
    close $fh or die (($e->{kind}||'') eq 'archive' ? "read failed for staged archive member $e->{archive}:$e->{member}\n" : "read failed for $e->{path}\n");
}

sub release_archive {
    my ($self,$archive)=@_;
    my $dir=delete $self->{archive_cache_dir}{$archive};
    delete $self->{archive_cache}{$archive};
    remove_tree($dir) if defined($dir) && -d $dir;
    return 1;
}

sub DESTROY {
    my ($self)=@_;
    my $tmp=$self->{archive_tmp_root};
    remove_tree($tmp) if defined($tmp) && -d $tmp;
}

sub day_map {
    my ($self,%opt)=@_; my %days;
    for my $e (@{$self->entries(%opt)}) {
        my $k=join('/', $e->{host},$e->{date});
        $days{$k} ||= {host=>$e->{host},date=>$e->{date},entries=>{}};
        $days{$k}{entries}{$e->{type}}=$e;
    }
    return [ sort { $a->{date} cmp $b->{date} || $a->{host} cmp $b->{host} } values %days ];
}

1;
