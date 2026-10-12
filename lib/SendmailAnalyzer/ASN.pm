package SendmailAnalyzer::ASN;

use strict;
use warnings;
use utf8;
use Socket qw(AF_INET AF_INET6 inet_pton);

sub new {
    my ($class,%opt)=@_;

    my $self=bless {
        db_file => defined($opt{db_file}) ? $opt{db_file} : '',
        reader  => undef,
        cache   => {},
        enabled => 0,
        reason  => 'not_configured',
    },$class;

    if ($opt{reader}) {
        $self->{reader}=$opt{reader};
        $self->{enabled}=1;
        $self->{reason}='ready';
        return $self;
    }

    my $file=$self->{db_file};

    return $self if !defined($file) || $file eq '';

    if (!-e $file) {
        $self->{reason}='db_not_found';
        return $self;
    }

    if (!-f $file) {
        $self->{reason}='db_not_file';
        return $self;
    }

    if (!-r $file) {
        $self->{reason}='db_not_readable';
        return $self;
    }

    my $module_ok=eval {
        require MaxMind::DB::Reader;
        1;
    };

    if (!$module_ok) {
        $self->{reason}='module_unavailable';
        return $self;
    }

    my $reader=eval {
        MaxMind::DB::Reader->new(file=>$file);
    };

    if (!$reader) {
        $self->{reason}='db_open_failed';
        return $self;
    }

    $self->{reader}=$reader;
    $self->{enabled}=1;
    $self->{reason}='ready';

    return $self;
}

sub _valid_ip {
    my ($ip)=@_;

    return 0 if !defined($ip) || $ip eq '';

    return 1 if eval { defined inet_pton(AF_INET,$ip) };
    return 1 if eval { defined inet_pton(AF_INET6,$ip) };

    return 0;
}

sub lookup {
    my ($self,$ip)=@_;

    return undef if !$self->{enabled};

    $ip='' if !defined $ip;
    $ip =~ s/^\s+|\s+$//g;

    return undef if !_valid_ip($ip);

    return $self->{cache}{$ip}
        if exists $self->{cache}{$ip};

    my $record=eval {
        $self->{reader}->record_for_address($ip);
    };

    if (!$record || ref($record) ne 'HASH') {
        $self->{cache}{$ip}=undef;
        return undef;
    }

    my $asn=$record->{autonomous_system_number};
    my $organization=$record->{autonomous_system_organization};

    $asn=undef
        if !defined($asn) || $asn !~ /^\d+$/;

    $organization=undef
        if !defined($organization) || ref($organization);

    if (!defined($asn) && (!defined($organization) || $organization eq '')) {
        $self->{cache}{$ip}=undef;
        return undef;
    }

    my $result={
        asn          => defined($asn) ? 0+$asn : undef,
        organization => defined($organization) ? "$organization" : undef,
    };

    $self->{cache}{$ip}=$result;

    return $result;
}

sub status {
    my ($self)=@_;

    return {
        enabled       => $self->{enabled} ? 1 : 0,
        reason        => $self->{reason},
        db_file       => $self->{db_file},
        cache_entries => 0+scalar(keys %{$self->{cache}}),
    };
}

1;
