use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $h,'<',$f or die$!; local$/; <$h> }
my $u=slurp("$root/bin/sa10_upgrade_from_94");
like($u,qr/Existing v10 databases are not a reason to skip 9\.4/,'existing v10 DB does not suppress legacy history');
like($u,qr/VACUUM INTO/,'existing SQLite is copied consistently before merge');
like($u,qr/sa10_import_legacy.*--db.*\$tmp/s,'legacy history is imported into the temporary merge database');
like($u,qr/pre-legacy-merge/,'pre-merge rollback SQLite is retained');
like($u,qr/retired-9\.4-\*\/usr-local-sendmailanalyzer\/data/,'retired 9.4 backup is an automatic history source');
like($u,qr/exact_mismatches/,'historical merge is audited before activation');
unlike($u,qr/preflight blocked: Queue-IDs reused across days/,'reused Queue-ID is no longer a fatal preflight condition');
like($u,qr/disambiguated internally/,'upgrade reports supported Queue-ID generation disambiguation');
my $a=slurp("$root/lib/SendmailAnalyzer/MigrationAudit.pm");
for my $type (qw(envelope delivery spam virus_verdict dsn smtp_auth smtp_reject)) {
    like($a,qr/source='legacy'.*\Q$type\E/s,"exact audit isolates legacy $type evidence");
}
my $p=slurp("$root/debian/preinst");
like($p,qr/systemctl stop sendmailanalyzer-collector\.service/,'package freezes current v10 collector before merge');
like($p,qr/systemctl stop sendmailanalyzer\.service/,'package freezes legacy 9.4 daemon before final data snapshot');
done_testing;
