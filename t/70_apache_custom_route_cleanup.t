use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use FindBin qw($Bin);
my $root="$Bin/.."; my $tmp=tempdir(CLEANUP=>1); make_path("$tmp/sites-available","$tmp/conf-available","$tmp/backups");
open my $fh,'>',"$tmp/sites-available/mailhost.conf" or die $!; print {$fh} <<'CONF'; close $fh;
<VirtualHost *:443>
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
 # stale route from an older package revision
 RedirectMatch 301 ^/sareport$ /sareport/
 ProxyPass /sareport/ http://127.0.0.1:9080/
 ProxyPassReverse /sareport/ http://127.0.0.1:9080/
 <Location /sareport/>
  Require local
  RequestHeader set X-Forwarded-Prefix "/sareport"
 </Location>
</VirtualHost>
CONF
open $fh,'>',"$tmp/conf-available/sendmailanalyzer.conf" or die $!; print {$fh} <<'DEF'; close $fh;
# package default
RedirectMatch 301 ^/sareport$ /sareport/
ProxyPass /sareport/ http://127.0.0.1:9080/
ProxyPassReverse /sareport/ http://127.0.0.1:9080/
<Location /sareport/>
 Require local
 RequestHeader set X-Forwarded-Prefix "/sareport"
</Location>
DEF
local $ENV{SENDMAILANALYZER_APACHE_ROOT}=$tmp;
my $out=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`; is($?,0,'Apache cleanup succeeds');
open my $rf,'<',"$tmp/sites-available/mailhost.conf" or die $!; local $/; my $site=<$rf>; close $rf;
open $rf,'<',"$tmp/conf-available/sendmailanalyzer.conf" or die $!; local $/; my $def=<$rf>; close $rf;
like($site,qr{ProxyPass\s+/reports/\s+http://127\.0\.0\.1:9080/},'custom /reports route is preserved');
unlike($def,qr{/sareport/},'redundant package /sareport route is removed when custom route exists');
unlike($site,qr{/sareport/},'redundant vhost /sareport route is removed when custom /reports exists');
like($out,qr/changed=2/,'cleanup is reported as a configuration change');
done_testing;
