use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $root="$Bin/.."; sub slurp{my($f)=@_;open my $h,'<',$f or die$!;local$/;<$h>}
my $pre=slurp("$root/debian/preinst");
like($pre,qr/sendmailanalyzer-9\.4-program\.preunpack\.tar\.gz/,'preinst still preserves a live legacy program tree if encountered');
my $p=slurp("$root/debian/postinst");
unlike($p,qr{/usr/bin/sa10_retire_94\b},'normal package configuration never retires 9.4 automatically');
unlike($p,qr{/usr/bin/sa10_upgrade_from_94\s+--config.*--auto},'normal package configuration never imports 9.4 automatically');
my $ret=slurp("$root/bin/sa10_retire_94");
like($ret,qr{/usr/local/sendmailanalyzer},'manual retirement helper remains available');
like($ret,qr{/var/backups/sendmailanalyzer|BACKUP_ROOT},'manual retirement helper uses canonical rollback area');
done_testing;
