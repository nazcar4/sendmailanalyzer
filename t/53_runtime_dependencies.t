use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $c=slurp("$root/debian/control");
for my $pkg (qw(perl passwd acl util-linux systemd tar gzip libdbi-perl libdbd-sqlite3-perl libplack-perl liburi-perl)) {
    like($c,qr/^Depends:.*\b\Q$pkg\E\b/m,"runtime dependency $pkg is declared");
}
like($c,qr/^Recommends:.*\bapache2\b.*\brsyslog\b/m,'Apache and rsyslog are recommended');
my $d=slurp("$root/docs/DEPENDENCIES.md");
for my $pkg (qw(acl util-linux systemd tar gzip libdbi-perl libdbd-sqlite3-perl libplack-perl liburi-perl)) {
    like($d,qr/`\Q$pkg\E`/,"dependency $pkg is documented");
}
like($d,qr/apt install \.\/sendmailanalyzer_VERSION_all\.deb/,'APT installation is documented');
done_testing;
