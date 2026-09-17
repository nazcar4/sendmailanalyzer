use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $post=slurp("$root/debian/postinst");
unlike($post,qr{/usr/bin/sa10_upgrade_from_94\s+--config.*--auto},'postinst never invokes automatic 9.4 migration');
unlike($post,qr{/usr/bin/sa10_retire_94\b},'postinst never retires 9.4 automatically');
like($post,qr/Existing v10 SQLite detected: preserved in place/,'existing v10 SQLite is explicitly authoritative');
like($post,qr/legacy 9\.4 data was not imported automatically/,'fresh database initialization explicitly avoids legacy import');
like($post,qr/SendmailAnalyzer::Storage::SQLite->new\(file=>\$file\)/,'postinst initializes or schema-upgrades through canonical storage layer');
my $u=slurp("$root/bin/sa10_upgrade_from_94");
ok(length($u)>0,'manual 9.4 migration helper remains shipped for explicit use');
my $doc=slurp("$root/docs/MIGRATION-9.4.md");
like($doc,qr/manual|explicit/i,'legacy migration documentation states manual/explicit policy');
done_testing;
