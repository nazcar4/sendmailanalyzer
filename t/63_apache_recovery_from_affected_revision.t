use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use FindBin qw($Bin);
my $root="$Bin/.."; my $tmp=tempdir(CLEANUP=>1); make_path("$tmp/sites-available","$tmp/backups");
my $f="$tmp/sites-available/site.conf";
# Simulate affected 10.0.16-2: HTTP was converted, HTTPS lost its legacy Alias.
open my $fh,'>',$f or die$!; print {$fh} <<'NOW'; close $fh;
<VirtualHost *:80>
 ServerName mailhost.example.test
 # SendmailAnalyzer 10 - production reverse proxy
 RedirectMatch 301 ^/reports$ /reports/
 ProxyPass /reports/ http://127.0.0.1:9080/
 ProxyPassReverse /reports/ http://127.0.0.1:9080/
 <Location /reports/>
  Require all denied
  Require ip 127.0.0.1 ::1 192.0.2.0/24
  RequestHeader set X-Forwarded-Prefix "/reports"
 </Location>
 ProxyPass /.well-known !
</VirtualHost>
<VirtualHost *:443>
 ServerName mailhost.example.test
 ProxyPass /.well-known !
</VirtualHost>
NOW
open my $bf,'>',"$tmp/backups/site.conf.20260916-100349" or die$!; print {$bf} <<'OLD'; close $bf;
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
OLD
local $ENV{SENDMAILANALYZER_APACHE_ROOT}=$tmp;
my $out=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`; is($?,0,'repair run succeeds');
open my $rf,'<',$f or die$!; local$/; my $s=<$rf>; close$rf;
my $n=()=$s =~ m{^\s*ProxyPass\s+/reports/\s+http://127\.0\.0\.1:9080/}mg;
is($n,2,'missing HTTPS proxy is recovered from package backup');
my $acl=()=$s =~ /Require ip 127\.0\.0\.1 ::1 192\.0\.2\.0\/24/g; is($acl,2,'recovered HTTPS keeps historical ACL');
like($out,qr/changed=1 configured=2/,'one missing vhost repaired while both are recognized');
done_testing;
