use strict; use warnings; use utf8; use Test::More; use FindBin qw($Bin);
my $root="$Bin/..";
sub slurp { my($f)=@_; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; return <$fh>; }
my $rules=slurp("$root/debian/rules");
like($rules,qr/debian\/copyright.*\/copyright/,'Debian copyright is installed in package docs');
like($rules,qr/changelog\.Debian\.gz/,'Debian changelog is installed');
my $builder=slurp("$root/scripts/build-deb.sh");
like($builder,qr/dpkg-gencontrol\s+-psendmailanalyzer/,'convenience builder derives version and dependency metadata from Debian source control');

ok(
    index($builder,'VERSION=$(dpkg-parsechangelog -l "$ROOT/debian/changelog" -SVersion)') >= 0,
    'convenience builder derives its package version from Debian changelog'
);

ok(
    index($builder,'OUT=${1:-"$ROOT/sendmailanalyzer_${VERSION}_all.deb"}') >= 0,
    'convenience builder derives its default output filename from the package version'
);

ok(
    index($builder,'SOURCE_DATE_EPOCH=$(dpkg-parsechangelog -l "$ROOT/debian/changelog" -STimestamp)') >= 0,
    'convenience builder derives reproducible-build epoch from Debian changelog'
);

ok(
    index($rules,'SOURCE_DATE_EPOCH ?= $(shell dpkg-parsechangelog -STimestamp)') >= 0,
    'canonical Debian build derives reproducible-build epoch from Debian changelog'
);

unlike(
    $builder,
    qr/sendmailanalyzer_10\.0\.16-\d+_all\.deb/,
    'convenience builder has no hard-coded Debian revision output filename'
);

unlike(
    $builder,
    qr/SOURCE_DATE_EPOCH=\d{9,}/,
    'convenience builder has no hard-coded reproducible-build epoch'
);

unlike(
    $rules,
    qr/SOURCE_DATE_EPOCH\s*\?=\s*\d{9,}/,
    'canonical Debian build has no hard-coded reproducible-build epoch'
);

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


like(
    $builder,
    qr/debian\/config.*debian\/preinst.*debian\/postinst/s,
    'convenience builder ships Debconf config with maintainer scripts'
);

like(
    $builder,
    qr/debian\/templates/,
    'convenience builder ships Debconf templates'
);

like(
    $rules,
    qr/debian\/config.*debian\/preinst.*debian\/postinst/s,
    'canonical Debian build ships Debconf config with maintainer scripts'
);

like(
    $rules,
    qr/debian\/templates/,
    'canonical Debian build ships Debconf templates'
);


my $postinst=slurp("$root/debian/postinst");

unlike(
    $postinst,
    qr/SendmailAnalyzer\s+10\.0\.16-\d+\s+production upgrade configured successfully\./,
    'postinst success message has no hard-coded Debian revision'
);

like(
    $postinst,
    qr/SendmailAnalyzer production upgrade configured successfully\./,
    'postinst has a revision-independent success message'
);

done_testing;
