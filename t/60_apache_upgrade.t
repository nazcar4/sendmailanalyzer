use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use FindBin qw($Bin);
my $root="$Bin/.."; my $tmp=tempdir(CLEANUP=>1); my $sites="$tmp/sites-available"; make_path($sites);
my $f="$sites/site.conf"; open my $fh,'>',$f or die $!; print {$fh} <<'CONF'; close $fh;
<VirtualHost *:80>
 ServerName mailhost.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require all denied
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Directory>
 ProxyPass /.well-known !
</VirtualHost>
<VirtualHost *:443>
 ServerName mailhost.example.test
 Alias /reports /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require all denied
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Directory>
 ProxyPass /.well-known !
</VirtualHost>
CONF
local $ENV{SENDMAILANALYZER_APACHE_ROOT}=$tmp;
my $out=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`; is($?,0,'Apache migration helper succeeds');
open my $rf,'<',$f or die $!; local $/; my $s=<$rf>; close $rf;
my $proxy=()=$s =~ m{^\s*ProxyPass\s+/reports/\s+http://127\.0\.0\.1:9080/}mg;
is($proxy,2,'legacy /reports is migrated independently in HTTP and HTTPS vhosts');
my $prefix=()=$s =~ /X-Forwarded-Prefix "\/reports"/g; is($prefix,2,'prefix is present in both vhosts');
my $acl=()=$s =~ /Require ip 127\.0\.0\.1 ::1 192\.0\.2\.0\/24/g; is($acl,2,'legacy Require ACL is preserved per vhost');
unlike($s,qr{Alias\s+/reports},'legacy Alias is removed');
like($out,qr/changed=2 configured=2 urls=\/reports\//,'status reports both configured integrations');
my $before=$s; my $out2=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`; is($?,0,'second Apache run succeeds');
open $rf,'<',$f or die $!; local $/; my $after=<$rf>; close $rf;
is($after,$before,'Apache migration is byte-idempotent on second run');
like($out2,qr/changed=0 configured=2/,'already-correct v10 proxies are detected instead of triggering fresh package config');

my $post=do { local $/; open my $ph,'<',"$root/debian/postinst" or die $!; <$ph> };
like($post,qr/AP_CONFIGURED/,'postinst distinguishes already-configured Apache from no integration');
like($post,qr/if \[ "\$AP_CONFIGURED" -eq 0 \]/,'fresh package config is added only when no integration exists');
done_testing;
