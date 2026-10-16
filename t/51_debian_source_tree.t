use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
for my $f (qw(debian/control debian/changelog debian/rules debian/conffiles debian/config debian/templates debian/preinst debian/postinst debian/prerm debian/postrm debian/copyright debian/README.Debian debian/README.source debian/source/format)) {
    ok(-f "$root/$f","$f exists");
}
open my $cf,'<:encoding(UTF-8)',"$root/debian/control" or die $!; local $/; my $c=<$cf>;
like($c,qr/^Source: sendmailanalyzer$/m,'Debian source name is correct');
like($c,qr/^Package: sendmailanalyzer$/m,'Debian binary package name is correct');
open my $ch,'<:encoding(UTF-8)',"$root/debian/changelog" or die $!; local $/; my $cl=<$ch>;
open my $vf,'<:encoding(UTF-8)',"$root/VERSION" or die $!; my $base=<$vf>; close $vf; $base =~ s/\s+\z//;
like($cl,qr/^sendmailanalyzer \(\Q$base\E-\d+\)/,'Debian changelog uses the application version plus a Debian revision');
open my $sf,'<',"$root/debian/source/format" or die $!; my $fmt=<$sf>; $fmt =~ s/\s+\z//; is($fmt,'3.0 (native)','native source format is declared');
ok(-x "$root/debian/rules",'debian/rules is executable');
ok(-f "$root/config/sendmailanalyzer-rspamd.tmpfiles",'vendor tmpfiles ACL rule exists');
done_testing;
