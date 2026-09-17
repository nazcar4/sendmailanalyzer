use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Find;

my $root="$Bin/..";

sub slurp {
    my ($file)=@_;
    open my $fh,'<:raw',$file or die "$file: $!";
    local $/;
    return <$fh>;
}

sub text_files {
    my (@dirs)=@_;
    my @out;
    for my $dir (@dirs) {
        find({
            no_chdir=>1,
            wanted=>sub {
                return if !-f $_;
                return if $_ =~ m{/(?:MANIFEST\.sha256|LICENSE)$};
                push @out,$File::Find::name;
            },
        },"$root/$dir");
    }
    return @out;
}

my @functional=text_files(qw(lib web config examples));
my $functional=join "\n",map { slurp($_) } @functional;
unlike($functional,qr/\balmogavers\.net\b/i,'functional source contains no deployment-specific domain');
unlike($functional,qr{/assets/salogo|brand-logo|Sendmail\.org}i,'functional source contains no removed third-party logo integration');
ok(!-e "$root/web/assets/salogo.png",'legacy logo image is absent from the source tree');
like($functional,qr/X-Spam-Status/,'standard SpamAssassin header is present');
like($functional,qr/X-Rspamd-Action/,'standard Rspamd action header is present');
like($functional,qr/X-Spamd-Result/,'standard Rspamd result header is present');
like($functional,qr/X-Virus-Status/,'standard ClamAV milter header is present');

my %allowed_header=map { lc($_)=>1 } qw(
    X-Spam-Status X-Spam-Flag X-Spam-Level
    X-Rspamd X-Rspamd-Action X-Rspamd-Score X-Rspamd-Server X-Rspamd-Queue-Id X-Spamd-Result
    X-Virus-Status X-Virus-Scanned
    X-Forwarded-Prefix X-Content-Type-Options X-Frame-Options X-Header
);
my @header_scan=(@functional,text_files('t'));
my %unexpected_headers;
for my $file (@header_scan) {
    next if $file =~ m{/80_public_release_hygiene\.t$};
    my $text=slurp($file);
    while ($text =~ /\b(X-[A-Za-z][A-Za-z0-9-]*)\b/g) {
        $unexpected_headers{$1}=1 if !$allowed_header{lc($1)} && $1 !~ /^X-Custom-[A-Za-z0-9-]+$/i;
    }
}
is_deeply([sort keys %unexpected_headers],[],'fixtures and functional source use only documented standard/proxy/security X-headers');

sub fixture_ip_allowed {
    my ($ip)=@_;
    my @o=split /\./,$ip;
    return 0 if @o != 4 || grep { $_ > 255 } @o;
    return 1 if $o[0] == 127;
    return 1 if $o[0] == 192 && $o[1] == 0  && $o[2] == 2;
    return 1 if $o[0] == 198 && $o[1] == 51 && $o[2] == 100;
    return 1 if $o[0] == 203 && $o[1] == 0  && $o[2] == 113;
    return 0;
}
my %unexpected_ips;
for my $file (@header_scan) {
    next if $file =~ m{/80_public_release_hygiene\.t$};
    my $text=slurp($file);
    while ($text =~ /(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])/g) {
        $unexpected_ips{$1}=1 if !fixture_ip_allowed($1);
    }
}
is_deeply([sort keys %unexpected_ips],[],'fixtures contain only loopback or RFC documentation IPv4 addresses');

my @tests=text_files('t');
for my $file (@tests) {
    next if $file =~ m{/52_creator_metadata\.t$};
    next if $file =~ m{/80_public_release_hygiene\.t$};
    unlike(slurp($file),qr/\balmogavers\.net\b/i,"public fixture contains no deployment-specific domain: $file");
}


# Public tests/examples must not carry deployment-oriented short names.
my @deployment_named = grep { /(?:^|\/)\d+_ns_/ } @tests;
is_deeply(\@deployment_named,[],'public test filenames do not expose deployment-oriented host naming');

# Shipped examples use small synthetic daemon PIDs and explicit synthetic IDs.
my $example_log=slurp("$root/examples/blocklist.log");
unlike($example_log,qr/\[\d{5,}\]/,'shipped example contains no large production-like daemon PID');
unlike($example_log,qr/#\d{5,}/,'shipped example contains no large production-like Rspamd process ID');
like($example_log,qr/A1B2C3D4E5F/,'shipped example uses an explicit synthetic Queue-ID');
like($example_log,qr/TEST0000001\@mx\.example\.net/,'shipped example uses an explicit synthetic Message-ID');

# Installation instructions must not hard-code a Debian revision in package filenames.
my @install_docs=("$root/README.md","$root/docs/INSTALL.md","$root/docs/DEPENDENCIES.md","$root/scripts/install.sh","$root/debian/README.source");
for my $file (@install_docs) {
    unlike(slurp($file),qr/sendmailanalyzer_10\.0\.16-\d+_all\.deb/,
        "package-installation example is revision-independent: $file");
}

my @docs=(
    "$root/README.md",
    "$root/CHANGELOG-v10.md",
    "$root/NOTICE",
    "$root/config/sendmailanalyzer.conf",
    glob("$root/docs/*.md"),
    "$root/debian/README.Debian",
    "$root/debian/README.source",
    "$root/debian/changelog",
);
my $docs=join "\n",map { slurp($_) } @docs;
like($docs,qr/Configuration.*Installation.*Migration.*Security/is,'public documentation/configuration exposes the expected English sections');

my @secret_names;
find({
    no_chdir=>1,
    wanted=>sub {
        return if !-f $_;
        my $name=$File::Find::name;
        $name =~ s{^.*/}{};
        push @secret_names,$File::Find::name
            if $name =~ /^(?:\.env(?:\..*)?|credentials.*|secrets.*)$/i
            || $name =~ /\.(?:pem|key|p12|pfx)$/i;
    },
},$root);
is_deeply(\@secret_names,[],'no credential/private-key files are present in the source tree');

done_testing;
