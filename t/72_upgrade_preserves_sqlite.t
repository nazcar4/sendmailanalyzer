use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $root="$Bin/.."; sub slurp{my($f)=@_;open my $h,'<',$f or die$!;local$/;<$h>}
my $pre=slurp("$root/debian/preinst");
like($pre,qr/PRAGMA wal_checkpoint\(TRUNCATE\)/,'preinst checkpoints existing SQLite before snapshot');
like($pre,qr/PRAGMA quick_check/,'preinst validates existing SQLite before snapshot');
like($pre,qr/cp --reflink=auto -a "\$DB" "\$SNAP\/sendmailanalyzer\.sqlite3\.existing"/,'preinst stores an independent rollback snapshot');
like($pre,qr/collector\.state\.existing/,'preinst preserves collector state');
my $post=slurp("$root/debian/postinst");
like($post,qr/sendmailanalyzer\.sqlite3\.existing/,'postinst failure path can restore SQLite snapshot');
like($post,qr/collector\.state\.existing/,'postinst failure path can restore collector state');
like($post,qr/rm -f \/var\/lib\/sendmailanalyzer\/sendmailanalyzer\.sqlite3-wal \/var\/lib\/sendmailanalyzer\/sendmailanalyzer\.sqlite3-shm/,'rollback clears transient WAL/SHM before restoring snapshot');
like($post,qr/automatic SendmailAnalyzer 9\.4 migration is disabled/,'upgrade logs preservation policy explicitly');
done_testing;
