use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

my $helper="$Bin/../bin/sa10_site_setup";

open my $fh,'<',$helper or die "$helper: $!";
local $/;
my $source=<$fh>;
close $fh;

my ($validator) = $source =~ m{
    if \s* \[ \s* -n \s* "\$ADDRESS" \s* \] ; \s* then
    \s* perl \s+ -e \s+ '
    (.*?)
    \n \s* ' \s* "\$ADDRESS" \s* \|\|
}sx;

ok(
    defined($validator) && length($validator),
    'embedded IPv4 validator was found in sa10_site_setup'
);

SKIP: {
    skip 'IPv4 validator could not be extracted', 7
        if !defined($validator) || !length($validator);

    for my $ip (
        '192.0.2.44',
        '127.0.0.1',
        '203.0.113.255',
    ) {
        system('perl','-e',$validator,$ip);

        is(
            $? >> 8,
            0,
            "valid IPv4 accepted: $ip"
        );
    }

    for my $ip (
        join('.',256,0,0,1),
        '192.0.2',
        '192.0.2.44.5',
        '192.0.x.44',
    ) {
        system('perl','-e',$validator,$ip);

        isnt(
            $? >> 8,
            0,
            "invalid IPv4 rejected: $ip"
        );
    }
}

done_testing;
