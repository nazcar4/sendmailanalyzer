use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
ok(-x "$root/bin/sa10_prepare_logs",'log permission helper is executable');
my $s=slurp("$root/bin/sa10_prepare_logs");
like($s,qr/mail\.log|LOG_FILE/,'helper handles configured mail log');
like($s,qr/RSPAMD_LOG_FILE/,'helper handles configured Rspamd log');
like($s,qr/-name "\$base\.\[0-9\]\*"/,'helper includes numeric rotations and .gz suffixes');
like($s,qr/u:\$\{SERVICE_USER\}:r--/,'helper grants read-only file ACL');
like($s,qr/u:\$\{SERVICE_USER\}:--x/,'helper grants traversal-only Rspamd directory ACL');
like($s,qr/d:u:\$\{SERVICE_USER\}:r-x/,'helper sets default Rspamd ACL for future files');
my $tmp=slurp("$root/config/sendmailanalyzer-rspamd.tmpfiles");
like($tmp,qr/u:sendmailanalyzer:--x/,'tmpfiles persists traversal ACL');
like($tmp,qr/d:u:sendmailanalyzer:r-x/,'tmpfiles persists default ACL');
my $post=slurp("$root/debian/postinst");
like($post,qr{/usr/bin/sa10_prepare_logs \"?\$CONF\"?},'postinst repairs log access automatically');
like($post,qr/usermod -a -G adm sendmailanalyzer/,'postinst preserves Debian adm access model');
done_testing;
