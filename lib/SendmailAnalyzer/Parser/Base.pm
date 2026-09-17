package SendmailAnalyzer::Parser::Base;
use strict;
use warnings;
use SendmailAnalyzer::TimeUtil;

sub split_prefix {
    my ($class, $raw, %opt) = @_;
    return SendmailAnalyzer::TimeUtil->parse_prefix($raw, %opt);
}

sub strip_prefix {
    my ($class, $raw, %opt) = @_;
    my ($line) = $class->split_prefix($raw, %opt);
    return $line;
}

sub event_common {
    my ($class, $raw, %opt) = @_;
    my ($line,$ts,$host) = $class->split_prefix($raw, %opt);
    return ($line, { timestamp => $ts, host => $host, raw => $raw });
}

sub parse_relay {
    my ($class, $value) = @_;
    return (undef, undef, undef) if !defined $value || $value eq '';
    if ($value =~ /^(.+?)\[([^\]]+)\](?::(\d+))?$/) { return ($1,$2,defined $3 ? 0+$3 : undef); }
    if ($value =~ /^\[([^\]]+)\](?::(\d+))?$/) { return (undef,$1,defined $2 ? 0+$2 : undef); }
    return ($value, undef, undef);
}

sub parse_kv_tail {
    my ($class, $tail) = @_;
    my %kv;
    while ($tail =~ /(?:^|[,;]\s*|\s+)([A-Za-z_][A-Za-z0-9_-]*)=([^,;\s]+|<[^>]*>)/g) {
        my ($k,$v)=($1,$2); $v =~ s/^<|>$//g; $kv{$k}=$v;
    }
    return \%kv;
}
1;
