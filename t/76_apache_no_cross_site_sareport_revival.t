use strict; use warnings; use Test::More; use FindBin qw($Bin); use File::Temp qw(tempdir); use File::Path qw(make_path);
my $root="$Bin/.."; my $tmp=tempdir(CLEANUP=>1);
make_path("$tmp/sites-available","$tmp/conf-available","$tmp/backups");
sub put { my($f,$s)=@_; open my $h,'>',$f or die "$f: $!"; print {$h} $s; close $h; }
put("$tmp/sites-available/example.test.conf", <<'CONF');
<VirtualHost *:80>
 ServerName example.test
 RedirectMatch 301 ^/reports$ /reports/
 ProxyPass /reports/ http://127.0.0.1:9080/
 ProxyPassReverse /reports/ http://127.0.0.1:9080/
 <Location /reports/>
  Require ip 127.0.0.1 ::1 192.0.2.0/24
  RequestHeader set X-Forwarded-Prefix "/reports"
 </Location>
</VirtualHost>
CONF
put("$tmp/sites-available/mail.example.test.conf", <<'CONF');
<VirtualHost *:80>
 ServerName mail.example.test
 RedirectMatch 301 ^/sareport$ /sareport/
 ProxyPass /sareport/ http://127.0.0.1:9080/
 ProxyPassReverse /sareport/ http://127.0.0.1:9080/
 <Location /sareport/>
  Require ip 127.0.0.1 ::1 192.0.2.0/24
  RequestHeader set X-Forwarded-Prefix "/sareport"
 </Location>
</VirtualHost>
CONF
# Stale backup contains a legacy Alias.  10.0.16-10 could use this cross-file
# recovery path after deleting /sareport/ and resurrect the deprecated route.
put("$tmp/backups/sites-available__mail.example.test.conf.20260916-100349", <<'CONF');
<VirtualHost *:80>
 ServerName mail.example.test
 Alias /sareport /usr/local/sendmailanalyzer/www
 <Directory /usr/local/sendmailanalyzer/www>
  Require ip 127.0.0.1 ::1 192.0.2.0/24
 </Directory>
</VirtualHost>
CONF
local $ENV{SENDMAILANALYZER_APACHE_ROOT}=$tmp;
my $out=`$^X $root/bin/sa10_apache_upgrade --apply --backup-dir $tmp/backups 2>&1`;
is($?,0,'Apache migration succeeds in cross-site stale-backup scenario') or diag $out;
open my $a,'<',"$tmp/sites-available/example.test.conf" or die $!; local $/; my $reports=<$a>; close $a;
open my $n,'<',"$tmp/sites-available/mail.example.test.conf" or die $!; local $/; my $mailhost=<$n>; close $n;
like($reports,qr{ProxyPass\s+/reports/\s+http://127\.0\.0\.1:9080/},'live /reports route is preserved');
like($reports,qr{Require ip 127\.0\.0\.1 ::1 192\.0\.2\.0/24},'live /reports ACL is preserved');
unlike($mailhost,qr{/sareport(?:10)?/},'deprecated routes are removed and not revived from stale backup');
unlike($out,qr{urls=.*sareport},'migration summary does not advertise deprecated route');
done_testing;
