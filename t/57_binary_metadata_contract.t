use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $rules=slurp("$root/debian/rules");
like($rules,qr/debian\/copyright.*\/copyright/,'Debian copyright is installed in package docs');
like($rules,qr/changelog\.Debian\.gz/,'Debian changelog is installed');
my $builder=slurp("$root/scripts/build-deb.sh");
like($builder,qr/dpkg-gencontrol\s+-psendmailanalyzer/,'convenience builder derives version and dependency metadata from Debian source control');
like($builder,qr/sendmailanalyzer_10\.0\.16-17_all\.deb/,'convenience builder defaults to current Debian revision output name');
like($builder,qr/debian\/copyright/,'convenience builder ships copyright credits');
like(
    $builder,
    qr/README\.DOCS\.md/,
    'convenience builder gives docs README a collision-free package name'
);
unlike(
    $builder,
    qr/README\.md".*docs"\/\*\.md/s,
    'convenience builder does not copy colliding README files in one operation'
);

like(
    $rules,
    qr/README\.DOCS\.md/,
    'canonical Debian build gives docs README a collision-free package name'
);
unlike(
    $rules,
    qr/^.*README\.md[^\n]*docs\/\*\.md[^\n]*$/m,
    'canonical Debian build avoids README basename collision'
);

ok(
    index($builder,'[ -f "$b" ] && [ -x "$b" ] || continue') >= 0,
    'convenience builder links only executable bin files'
);

ok(
    index($rules,'[ -f "$$b" ] && [ -x "$$b" ] || continue') >= 0,
    'canonical Debian build links only executable bin files'
);

ok(
    !-x "$root/bin/README.md",
    'bin README is documentation, not an executable command'
);

like(
    $builder,
    qr/find "\$PKG\/usr\/lib\/sendmailanalyzer\/bin" -type f -exec chmod 0644/,
    'convenience builder defaults bin files to non-executable permissions'
);

like(
    $rules,
    qr/find \$\(PKGDIR\)\/usr\/lib\/sendmailanalyzer\/bin -type f -exec chmod 0644/,
    'canonical Debian build defaults bin files to non-executable permissions'
);

unlike(
    $builder,
    qr/find "\$PKG\/usr\/lib\/sendmailanalyzer\/bin" -type f -exec chmod 0755/,
    'convenience builder does not mark all bin files executable'
);

unlike(
    $rules,
    qr/find \$\(PKGDIR\)\/usr\/lib\/sendmailanalyzer\/bin -type f -exec chmod 0755/,
    'canonical Debian build does not mark all bin files executable'
);

done_testing;
