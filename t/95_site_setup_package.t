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

my $helper=slurp("$root/bin/sa10_site_setup");
my $post=slurp("$root/debian/postinst");
my $config=slurp("$root/debian/config");
my $templates=slurp("$root/debian/templates");
my $control=slurp("$root/debian/control");
my $rules=slurp("$root/debian/rules");
my $builder=slurp("$root/scripts/build-deb.sh");

ok(
    -x "$root/bin/sa10_site_setup",
    'dedicated-site helper is executable'
);

like(
    $helper,
    qr/ProxyPass\s+\/\s+http:\/\/127\.0\.0\.1:9080\//,
    'dedicated vhost reverse-proxies its root'
);

like(
    $helper,
    qr/AuthType Basic/,
    'dedicated vhost uses Basic Auth'
);

like(
    $helper,
    qr/Require ip 127\.0\.0\.1 ::1/,
    'localhost bypass is explicit'
);

like(
    $helper,
    qr/Require user \$USERNAME/,
    'WAN access is tied to the configured username'
);

like(
    $helper,
    qr/htpasswd\s+\\?\s*-B.*?-i/s,
    'bcrypt htpasswd reads the password from stdin'
);

unlike(
    $helper,
    qr/htpasswd[^\n]*\$SITE_PASSWORD/,
    'clear-text password is not an htpasswd command argument'
);

like(
    $helper,
    qr/-checkend 0/,
    'certificate expiry is checked'
);

like(
    $helper,
    qr/-checkhost "\$FQDN"/,
    'certificate hostname coverage is checked'
);

like(
    $helper,
    qr/named-checkzone "\$DOMAIN"/,
    'candidate BIND zones are validated'
);

like(
    $helper,
    qr/dnssec-signzone\s+\\.*?-o "\$DOMAIN".*?-3 -.*?-H 0.*?-u/s,
    'manual DNSSEC uses the established signing policy'
);

like(
    $helper,
    qr/dnssec-verify\s+\\.*?-o "\$DOMAIN"/s,
    'new signed zone is verified'
);

like(
    $helper,
    qr/zone_is_dynamic_or_inline/,
    'dynamic or BIND-managed signing is detected separately'
);

like(
    $helper,
    qr/zone\.original/,
    'DNS rollback copy is created'
);

like(
    $helper,
    qr/refusing overwrite/,
    'conflicting A records are not overwritten'
);

unlike(
    $helper,
    qr/dnssec-keygen/,
    'helper never creates DNSSEC keys'
);

unlike(
    $helper,
    qr/(?:cron|crontab).*dnssec-signzone/i,
    'helper installs no DNSSEC signing schedule'
);

like(
    $config,
    qr/sendmailanalyzer\/site_domain/,
    'Debconf collects the base domain'
);

like(
    $templates,
    qr/Template: sendmailanalyzer\/site_password.*?Type: password/s,
    'Debconf password question has password type'
);

like(
    $post,
    qr/sa10_site_setup/,
    'postinst invokes dedicated-site helper'
);

like(
    $post,
    qr/db_set sendmailanalyzer\/site_password ''/,
    'postinst clears Debconf clear-text password'
);

like(
    $control,
    qr/^Depends:.*\bdebconf\b/m,
    'Debconf is a hard package dependency'
);

for my $pkg (qw(apache2 apache2-utils bind9-utils openssl rsyslog)) {
    like(
        $control,
        qr/^Recommends:.*\b\Q$pkg\E\b/m,
        "$pkg is recommended"
    );
}

like(
    $rules,
    qr/debian\/config.*debian\/preinst.*debian\/postinst/s,
    'canonical builder packages Debconf config'
);

like(
    $rules,
    qr/debian\/templates/,
    'canonical builder packages Debconf templates'
);

like(
    $builder,
    qr/debian\/config.*debian\/preinst.*debian\/postinst/s,
    'convenience builder packages Debconf config'
);

like(
    $builder,
    qr/debian\/templates/,
    'convenience builder packages Debconf templates'
);

unlike(
    join("\n",$helper,$config,$templates),
    qr/\balmogavers\.net\b/i,
    'automatic site setup contains no deployment-specific domain'
);

done_testing;
