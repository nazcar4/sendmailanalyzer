use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);

use lib "$Bin/../lib";
use SendmailAnalyzer::ASN;

{
    package Local::ASNReader;

    sub new {
        return bless {calls=>{}},shift;
    }

    sub record_for_address {
        my ($self,$ip)=@_;

        $self->{calls}{$ip}++;

        return {
            autonomous_system_number       => 64500,
            autonomous_system_organization => 'Example Documentation ASN',
        } if $ip eq '192.0.2.10';

        return {
            autonomous_system_number       => 64501,
            autonomous_system_organization => 'Example IPv6 Documentation ASN',
        } if $ip eq '2001:db8::10';

        die "synthetic reader failure"
            if $ip eq '203.0.113.9';

        return undef;
    }

    sub calls {
        my ($self,$ip)=@_;
        return 0+($self->{calls}{$ip}||0);
    }
}

my $disabled=SendmailAnalyzer::ASN->new;

is(
    $disabled->status->{enabled},
    0,
    'ASN disabled without configuration'
);

is(
    $disabled->status->{reason},
    'not_configured',
    'missing configuration is reported'
);

ok(
    !defined($disabled->lookup('192.0.2.10')),
    'disabled ASN performs no lookup'
);

my $missing=SendmailAnalyzer::ASN->new(
    db_file=>'/definitely/not/a/real/GeoLite2-ASN.mmdb'
);

is(
    $missing->status->{enabled},
    0,
    'missing database does not enable ASN'
);

is(
    $missing->status->{reason},
    'db_not_found',
    'missing database is non-fatal'
);

my $reader=Local::ASNReader->new;

my $asn=SendmailAnalyzer::ASN->new(
    reader=>$reader,
    db_file=>'/synthetic/GeoLite2-ASN.mmdb',
);

is(
    $asn->status->{enabled},
    1,
    'injected reader enables ASN'
);

is(
    $asn->status->{reason},
    'ready',
    'enabled ASN reports ready'
);

ok(
    !defined($asn->lookup('not-an-ip')),
    'invalid address is rejected'
);

is(
    $reader->calls('not-an-ip'),
    0,
    'invalid address never reaches reader'
);

my $v4=$asn->lookup('192.0.2.10');

is($v4->{asn},64500,'IPv4 ASN returned');

is(
    $v4->{organization},
    'Example Documentation ASN',
    'IPv4 organization returned'
);

is(
    $reader->calls('192.0.2.10'),
    1,
    'IPv4 reader called once'
);

my $v4_cached=$asn->lookup(' 192.0.2.10 ');

is(
    $v4_cached->{asn},
    64500,
    'surrounding whitespace accepted'
);

is(
    $reader->calls('192.0.2.10'),
    1,
    'IPv4 positive lookup cached'
);

my $v6=$asn->lookup('2001:db8::10');

is($v6->{asn},64501,'IPv6 ASN returned');

is(
    $v6->{organization},
    'Example IPv6 Documentation ASN',
    'IPv6 organization returned'
);

is(
    $reader->calls('2001:db8::10'),
    1,
    'IPv6 reader called once'
);

ok(
    !defined($asn->lookup('198.51.100.20')),
    'missing ASN record returns undef'
);

ok(
    !defined($asn->lookup('198.51.100.20')),
    'missing ASN record remains undef'
);

is(
    $reader->calls('198.51.100.20'),
    1,
    'negative lookup cached'
);

ok(
    !defined($asn->lookup('203.0.113.9')),
    'reader error is non-fatal'
);

ok(
    !defined($asn->lookup('203.0.113.9')),
    'reader error result remains cached'
);

is(
    $reader->calls('203.0.113.9'),
    1,
    'failing lookup is not repeated'
);

is(
    $asn->status->{cache_entries},
    4,
    'cache statistics are correct'
);

done_testing;
