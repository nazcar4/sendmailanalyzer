use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<',$f or die $!; local $/; return <$fh>; }
my $control=slurp("$root/debian/control");
like($control,qr/^Source: sendmailanalyzer$/m,'source package is canonical sendmailanalyzer');
like($control,qr/^Package: sendmailanalyzer$/m,'binary package is canonical sendmailanalyzer');
like($control,qr/^Conflicts: sendmailanalyzer10$/m,'temporary package is conflicted');
like($control,qr/^Replaces: sendmailanalyzer10$/m,'temporary package is replaced');
unlike($control,qr/^Conflicts: sendmailanalyzer\s*\(/m,'package does not conflict with itself/9.4 package name');
my $rules=slurp("$root/debian/rules");
like($rules,qr{/usr/lib/sendmailanalyzer},'rules use /usr/lib/sendmailanalyzer');
like($rules,qr{/etc/sendmailanalyzer\.conf},'rules use /etc/sendmailanalyzer.conf');
like($rules,qr{usr/share/\$\(PACKAGE\)},'rules install under /usr/share/sendmailanalyzer through canonical package name');
unlike($rules,qr{/usr/lib/sendmailanalyzer10|/etc/sendmailanalyzer10\.conf},'final payload has no sendmailanalyzer10 path');
for my $svc (qw(sendmailanalyzer-collector.service sendmailanalyzer-web.service)) { ok(-f "$root/systemd/$svc","canonical service $svc exists"); }
ok(-f "$root/web/sendmailanalyzer.psgi",'canonical PSGI filename exists');
done_testing;
