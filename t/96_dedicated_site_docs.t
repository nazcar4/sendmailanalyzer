use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);

my $root="$Bin/..";

sub slurp {
    my ($file)=@_;
    open my $fh,'<:encoding(UTF-8)',$file or die "$file: $!";
    local $/;
    return <$fh>;
}

my $install=slurp("$root/docs/INSTALL.md");
my $config=slurp("$root/docs/CONFIGURATION.md");
my $migration=slurp("$root/docs/MIGRATION-9.4.md");
my $security=slurp("$root/docs/SECURITY.md");
my $deps=slurp("$root/docs/DEPENDENCIES.md");
my $readme=slurp("$root/README.md");
my $change=slurp("$root/CHANGELOG-v10.md");

like(
    $install,
    qr/dedicated HTTPS reporting site/i,
    'installation guide documents dedicated HTTPS deployment'
);

like(
    $install,
    qr/dnssec-signzone/i,
    'installation guide documents DNSSEC re-signing'
);

like(
    $install,
    qr/non-interactive installation/i,
    'non-interactive safe behavior is documented'
);

like(
    $install,
    qr/Basic Auth/i,
    'WAN authentication is documented'
);

like(
    $config,
    qr/reverse-proxies `\/` directly/i,
    'configuration guide documents root reverse proxy'
);

like(
    $migration,
    qr/dedicated HTTPS reporting subdomain/i,
    'migration guide documents the new preferred layout'
);

like(
    $security,
    qr/bcrypt htpasswd/i,
    'security guide documents bcrypt credential storage'
);

like(
    $security,
    qr/does not create, rotate or periodically maintain DNSSEC keys/i,
    'DNSSEC ownership boundary is documented'
);

for my $pkg (qw(debconf apache2-utils bind9-utils openssl)) {
    like(
        $deps,
        qr/`\Q$pkg\E`/,
        "dependency guide documents $pkg"
    );
}

like(
    $readme,
    qr/10\.0\.16-19/,
    'README documents Debian revision 10.0.16-19'
);

like(
    $change,
    qr/10\.0\.16-19/,
    'project changelog documents Debian revision 10.0.16-19'
);

my $combined=join "\n",$install,$config,$migration;

unlike(
    $combined,
    qr{`/reports/` is the recommended route},
    'legacy path is no longer advertised as the recommended layout'
);

done_testing;
