use strict; use warnings; use Test::More; use FindBin qw($Bin);
for my $f (qw(sa10_collect sa10_import_legacy)) {
  open my $fh,'<',"$Bin/../bin/$f" or die $!; local $/; my $s=<$fh>; close $fh;
  like($s,qr/Refusing to create\/write the service database as root/,$f.' guards service DB ownership');
  like($s,qr{/var/lib/sendmailanalyzer},$f.' guard targets service DB tree');
}
my $m=do { open my $fh,'<',"$Bin/../bin/sa10_migration_check" or die $!; local $/; <$fh> };
like($m,qr/service-user legacy read/,'migration preflight checks service-user legacy access');
like($m,qr/sample_sender_file/,'migration preflight verifies a real senders.dat file');
done_testing;
