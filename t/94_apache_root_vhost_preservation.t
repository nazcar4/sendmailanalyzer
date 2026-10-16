use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $root="$Bin/..";
my $tmp=tempdir(CLEANUP=>1);

make_path(
    "$tmp/sites-available",
    "$tmp/conf-available",
    "$tmp/backups"
);

sub put {
    my($file,$text)=@_;
    open my $fh,'>',$file or die "$file: $!";
    print {$fh} $text;
    close $fh;
}

sub get {
    my($file)=@_;
    open my $fh,'<',$file or die "$file: $!";
    local $/;
    return <$fh>;
}

my $reports="$tmp/sites-available/reports.example.test.conf";
my $mailhost="$tmp/sites-available/mailhost.example.test.conf";

put($reports, <<'CONF');
<VirtualHost *:80>
 ServerName reports.example.test
 Redirect permanent / https://reports.example.test/
</VirtualHost>

<VirtualHost *:443>
 ServerName reports.example.test

 ProxyPreserveHost On
 ProxyPass / http://127.0.0.1:9080/
 ProxyPassReverse / http://127.0.0.1:9080/

 <Location />
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Location>
</VirtualHost>
CONF

put($mailhost, <<'CONF');
<VirtualHost *:80>
 ServerName mailhost.example.test
 RedirectMatch 301 ^/reports$ https://reports.example.test/
 RedirectMatch 301 ^/reports/(.*)$ https://reports.example.test/$1
</VirtualHost>

<VirtualHost *:443>
 ServerName mailhost.example.test
 RedirectMatch 301 ^/reports$ https://reports.example.test/
 RedirectMatch 301 ^/reports/(.*)$ https://reports.example.test/$1
</VirtualHost>
CONF

# Historical backups deliberately contain the old path-based integration.
# A package upgrade must not revive it when a dedicated root vhost exists.
put("$tmp/backups/sites-available__reports.example.test.conf.20260916-100349", <<'CONF');
<VirtualHost *:80>
 ServerName reports.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Directory>
</VirtualHost>

<VirtualHost *:443>
 ServerName reports.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Directory>
</VirtualHost>
CONF

put("$tmp/backups/sites-available__mailhost.example.test.conf.20260916-100349", <<'CONF');
<VirtualHost *:80>
 ServerName mailhost.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require local
 </Directory>
</VirtualHost>

<VirtualHost *:443>
 ServerName mailhost.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require local
 </Directory>
</VirtualHost>
CONF

local $ENV{SENDMAILANALYZER_APACHE_ROOT}=$tmp;

my $out=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`;

is(
    $?,
    0,
    'Apache migration accepts a dedicated root vhost'
) or diag $out;

my $reports_after=get($reports);
my $mailhost_after=get($mailhost);
my $all=$reports_after."\n".$mailhost_after;

like(
    $reports_after,
    qr{^\s*ProxyPass\s+/\s+http://127\.0\.0\.1:9080/\s*$}m,
    'root SendmailAnalyzer ProxyPass is preserved'
);

like(
    $reports_after,
    qr{^\s*ProxyPassReverse\s+/\s+http://127\.0\.0\.1:9080/\s*$}m,
    'root SendmailAnalyzer ProxyPassReverse is preserved'
);

like(
    $reports_after,
    qr{Require ip 127\.0\.0\.1 ::1 192\.0\.2\.0/24},
    'root vhost ACL is preserved'
);

like(
    $mailhost_after,
    qr{RedirectMatch 301 \^/reports\$ https://reports\.example\.test/},
    'old bare reports URL remains an external redirect'
);

like(
    $mailhost_after,
    qr{RedirectMatch 301 \^/reports/\(\.\*\)\$ https://reports\.example\.test/\$1},
    'old reports subtree remains an external redirect'
);

unlike(
    $all,
    qr{^\s*ProxyPass\s+/reports/\s+http://127\.0\.0\.1:9080/\s*$}m,
    'old local /reports proxy is not revived'
);

unlike(
    $all,
    qr{^\s*Alias\s+/reports\b}m,
    'old /reports Alias is not revived'
);

unlike(
    $all,
    qr{X-Forwarded-Prefix\s+"/reports"},
    'obsolete /reports forwarded prefix is not revived'
);

unlike(
    $all,
    qr{/sareport(?:10)?/},
    'deprecated sareport routes are absent'
);

like(
    $out,
    qr/changed=0 configured=1 urls=\//,
    'root integration is reported as already configured'
);

my $reports_before_second=$reports_after;
my $mailhost_before_second=$mailhost_after;

my $out2=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`;

is(
    $?,
    0,
    'second migration run succeeds'
) or diag $out2;

is(
    get($reports),
    $reports_before_second,
    'dedicated root vhost is byte-idempotent'
);

is(
    get($mailhost),
    $mailhost_before_second,
    'external compatibility redirects are byte-idempotent'
);

like(
    $out2,
    qr/changed=0 configured=1 urls=\//,
    'second run still recognizes root integration'
);

done_testing;
