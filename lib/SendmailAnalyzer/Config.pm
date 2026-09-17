package SendmailAnalyzer::Config;
use strict;
use warnings;

sub defaults {
    return {
        LOG_FILE        => '/var/log/mail.log',
        RSPAMD_LOG_FILE => '/var/log/rspamd/rspamd.log',
        DB_FILE         => '/var/lib/sendmailanalyzer/sendmailanalyzer.sqlite3',
        STATE_FILE      => '/var/lib/sendmailanalyzer/collector.state',
        LOCAL_DOMAINS   => ['localhost'],
        BIND_HOST       => '127.0.0.1',
        BIND_PORT       => 9080,
        LEGACY_DATA_DIR => '/usr/local/sendmailanalyzer/data',
        RAW_RETENTION_DAYS => 31,
        WEB_PAGE_SIZE   => 100,
        MEMORY_MESSAGE_LIMIT => 10000,
        HOSTNAME        => '',
        CONFIG_DIR      => '/etc/sendmailanalyzer.d',
        HEADER_ROUTES   => {},
        HEADER_IGNORE   => {},
    };
}

sub _header_name {
    my ($value,$path,$line_no)=@_;
    $value =~ s/^\s+|\s+$//g;
    die "Invalid header name in $path line $line_no: $value\n"
        if $value !~ /^X-[A-Za-z0-9][A-Za-z0-9-]*$/i;
    return lc $value;
}

sub _load_file {
    my ($cfg,$path,%opt)=@_;
    open my $fh, '<', $path or die "Cannot open config $path: $!";
    my $line_no=0;
    while (my $line = <$fh>) {
        $line_no++;
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^#/;
        my ($key, $value) = split /\s+/, $line, 2;
        next if !defined $value;
        $value =~ s/^\s+|\s+$//g;
        if ($key eq 'LOCAL_DOMAINS') {
            my @v = grep { length } map { my $x=$_; $x =~ s/^\s+|\s+$//g; lc $x } split /,/, $value;
            $cfg->{$key} = \@v;
        } elsif ($key =~ /^(?:BIND_PORT|RAW_RETENTION_DAYS|WEB_PAGE_SIZE|MEMORY_MESSAGE_LIMIT)$/) {
            $cfg->{$key} = 0 + $value;
        } elsif ($key eq 'HEADER_ROUTE') {
            my ($header,$engine)=split /\s+/, $value, 2;
            die "HEADER_ROUTE requires: HEADER_ROUTE X-Header engine in $path line $line_no\n"
                if !defined($header) || !defined($engine);
            $engine =~ s/^\s+|\s+$//g;
            $engine=lc $engine;
            die "Unsupported HEADER_ROUTE engine '$engine' in $path line $line_no\n"
                if $engine !~ /^(?:rspamd|spamassassin|clamav)$/;
            $cfg->{HEADER_ROUTES}{_header_name($header,$path,$line_no)}=$engine;
        } elsif ($key eq 'HEADER_IGNORE') {
            my ($header,$extra)=split /\s+/, $value, 2;
            die "HEADER_IGNORE requires exactly one X-Header in $path line $line_no\n"
                if !defined($header) || defined($extra);
            $cfg->{HEADER_IGNORE}{_header_name($header,$path,$line_no)}=1;
        } elsif ($key eq 'CONFIG_DIR') {
            next if !$opt{allow_config_dir};
            $cfg->{$key} = $value;
        } else {
            $cfg->{$key} = $value;
        }
    }
    close $fh;
}

sub load {
    my ($class, $path) = @_;
    my $cfg = $class->defaults;
    return $cfg if !$path || !-e $path;
    _load_file($cfg,$path,allow_config_dir=>1);
    my $dir=$cfg->{CONFIG_DIR};
    if (defined($dir) && length($dir) && -d $dir) {
        opendir my $dh,$dir or die "Cannot open config directory $dir: $!";
        my @files=sort grep { /\.conf\z/ && -f "$dir/$_" } readdir $dh;
        closedir $dh;
        _load_file($cfg,"$dir/$_") for @files;
    }
    return $cfg;
}

1;
