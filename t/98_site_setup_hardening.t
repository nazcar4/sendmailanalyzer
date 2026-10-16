use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);

sub slurp {
    my ($path)=@_;

    open my $fh,'<',$path or die "$path: $!";
    local $/;
    my $text=<$fh>;
    close $fh;

    return $text;
}

my $helper  = slurp("$Bin/../bin/sa10_site_setup");
my $config  = slurp("$Bin/../debian/config");
my $postinst= slurp("$Bin/../debian/postinst");

like(
    $helper,
    qr/sub\s+not_used_never_match|cert_has_preferred_wildcard\(\)/,
    'wildcard preference helper exists'
);

like(
    $helper,
    qr/grep\s+-Fx\s+--\s+"\*\.\$DOMAIN"/s,
    'wildcard SAN preference is exact for the base domain'
);

like(
    $helper,
    qr/\$wildcard"\s+-gt\s+"\$best_wildcard"/s,
    'wildcard rank wins before certificate expiry'
);

like(
    $helper,
    qr/WARNING: Apache dedicated WAN site skipped because no unexpired local TLS certificate covers \$FQDN\./,
    'missing certificate is a safe WAN-site skip'
);

unlike(
    $helper,
    qr/fail\s+"no unexpired local TLS certificate covers \$FQDN"/,
    'missing certificate is no longer fatal'
);

like(
    $helper,
    qr/dnssec_mode='nsec3'/,
    'NSEC3 mode is detected'
);

like(
    $helper,
    qr/dnssec_mode='nsec'/,
    'NSEC mode is detected'
);

like(
    $helper,
    qr/nsec3\).*?-3\s+-.*?-H\s+0.*?-u/s,
    'NSEC3 signing retains the established NSEC3 policy'
);

like(
    $helper,
    qr/nsec\).*?dnssec-signzone.*?-o\s+"\$DOMAIN".*?-u.*?-f\s+"\$ZONE_SIGNED"/s,
    'NSEC signing does not force NSEC3'
);

like(
    $helper,
    qr/signed zone denial-of-existence mode is unknown; refusing automatic signing/,
    'unknown signed-zone denial mode fails safely'
);

like(
    $config,
    qr/existing_lan=''/,
    'Debconf detects an existing LAN ACL'
);

like(
    $config,
    qr/An already deployed dedicated root vhost is authoritative during upgrades\./,
    'existing dedicated vhost is explicitly authoritative'
);

like(
    $config,
    qr/db_set\s+sendmailanalyzer\/site_domain\s+"\$domain_default".*?
       db_set\s+sendmailanalyzer\/site_subdomain\s+"\$subdomain_default".*?
       db_set\s+sendmailanalyzer\/site_username\s+"\$username_default"/sx,
    'existing vhost overwrites stale Debconf identity values'
);

my $secret_clear_count = () =
    $postinst =~ /db_set sendmailanalyzer\/site_password ''/g;

cmp_ok(
    $secret_clear_count,
    '>=',
    3,
    'Debconf password is cleared on both helper failures and normal completion'
);

done_testing;
