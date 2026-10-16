use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $w="$Bin/../web/sendmailanalyzer.psgi"; open my $fh,'<',$w or die $!; local $/; my $s=<$fh>; close $fh;
like($s,qr/Content-Security-Policy.*style-src 'self'.*script-src 'self'/,'strict self-only CSP retained');
unlike($s,qr/style\s*=\s*["']/i,'web output source contains no inline style attributes');
like($s,qr/<svg class="bigchart"/,'activity chart uses SVG rather than inline CSS heights');
my $st="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm"; open my $sf,'<',$st or die $!; local $/; my $ss=<$sf>; close $sf;
like($ss,qr/\$limit=100 if \$limit<1; \$limit=500 if \$limit>500/,'message API storage limit is clamped to 1..500 policy');
like($ss,qr/\$attr\{ReadOnly\}=1 if \$readonly/,'read-only storage connection requests DBI ReadOnly');
like($s,qr/sub request_prefix/,'reverse-proxy prefix helper exists');
like($s,qr/HTTP_X_FORWARDED_PREFIX/,'reverse-proxy prefix comes from explicit forwarded header');
my $a=do { open my $af,'<',"$Bin/../config/apache2-sendmailanalyzer.conf" or die $!; local $/; <$af> };
like(
    $a,
    qr/ProxyPass\s+\/\s+http:\/\/127\.0\.0\.1:9080\//,
    'Apache example reverse-proxies the dedicated site root'
);
like(
    $a,
    qr/AuthType\s+Basic/,
    'Apache example protects WAN access with Basic Auth'
);
like(
    $a,
    qr/Require\s+user\s+sendmailreports/,
    'Apache example contains the dedicated WAN user'
);
like(
    $a,
    qr/Require\s+ip\s+127\.0\.0\.1\s+::1\s+192\.0\.2\.0\/24/,
    'Apache example allows localhost and documentation LAN directly'
);
unlike(
    $a,
    qr/X-Forwarded-Prefix\s+"\/reports"/,
    'dedicated root deployment does not use the legacy reports prefix'
);
done_testing;
