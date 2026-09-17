package SendmailAnalyzer::TimeUtil;
use strict;
use warnings;
use Time::Local qw(timelocal timegm);
use POSIX qw(strftime);

my %MON = (Jan=>0,Feb=>1,Mar=>2,Apr=>3,May=>4,Jun=>5,Jul=>6,Aug=>7,Sep=>8,Oct=>9,Nov=>10,Dec=>11);

sub parse_prefix {
    my ($class, $raw, %opt) = @_;
    my $line = $raw;
    chomp $line;
    if ($line =~ s/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))\s+(\S+)\s+//) {
        return ($line, $1, $2);
    }
    if ($line =~ s/^([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\S+)\s+//) {
        my ($mon,$day,$h,$m,$s,$host)=($1,$2,$3,$4,$5,$6);
        my $year = $opt{year} || (localtime)[5] + 1900;
        my $iso = sprintf('%04d-%02d-%02dT%02d:%02d:%02d', $year, $MON{$mon}+1, $day, $h,$m,$s);
        return ($line, $iso, $host);
    }
    return ($line, undef, undef);
}

sub date_key {
    my ($class, $ts) = @_;
    return undef if !defined $ts;
    return $1 if $ts =~ /^(\d{4}-\d{2}-\d{2})/;
    return undef;
}

sub now_iso { return strftime('%Y-%m-%dT%H:%M:%S%z', localtime); }
1;
