use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $rules=slurp("$root/debian/rules");
like($rules,qr/debian\/copyright.*\/copyright/,'Debian copyright is installed in package docs');
like($rules,qr/changelog\.Debian\.gz/,'Debian changelog is installed');
my $builder=slurp("$root/scripts/build-deb.sh");
like($builder,qr/dpkg-gencontrol\s+-psendmailanalyzer/,'convenience builder derives version and dependency metadata from Debian source control');
like($builder,qr/sendmailanalyzer_10\.0\.16-16_all\.deb/,'convenience builder defaults to current Debian revision output name');
like($builder,qr/debian\/copyright/,'convenience builder ships copyright credits');
done_testing;
