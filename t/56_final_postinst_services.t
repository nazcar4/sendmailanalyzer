use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $p=slurp("$root/debian/postinst");
my $pos_db=index($p,'Validating/preserving the production SQLite database');
my $pos_self=index($p,'sa10_selftest');
my $pos_enable=index($p,'systemctl enable sendmailanalyzer-collector.service sendmailanalyzer-web.service');
ok($pos_db>=0 && $pos_self>$pos_db && $pos_enable>$pos_self,'services are enabled only after existing/fresh SQLite validation and selftest');
like($p,qr/systemctl restart sendmailanalyzer-collector\.service/,'collector is restarted after upgrade');
like($p,qr/systemctl restart sendmailanalyzer-web\.service/,'web is restarted after upgrade');
like($p,qr/\[ -d \/run\/systemd\/system \]/,'service activation is skipped safely in non-systemd build/chroot environments');
my $r=slurp("$root/README.md");
like($r,qr/does not restart Postfix, Rspamd, Dovecot, rsyslog, SSH/i,'documentation states critical mail/network services are not restarted');
like($r,qr/Apache.*reload/is,'documentation limits Apache action to reload');
done_testing;
