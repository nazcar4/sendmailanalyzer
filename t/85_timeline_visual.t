use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);

my $web="$Bin/../web/sendmailanalyzer.psgi";
open my $fh,'<:encoding(UTF-8)',$web or die $!;
local $/;
my $s=<$fh>;
close $fh;

like($s,qr/sub timeline_event_meta/,'timeline has event classification helper');
like($s,qr/sub timeline_event_html/,'timeline has dedicated event renderer');

like($s,qr/Reject.*bad.*reject/s,'reject events have red classification');
like($s,qr/Delivery.*good.*delivery/s,'delivery events have green classification');
like($s,qr/Spam filter.*warn.*filter/s,'spam filter events have filter classification');
like($s,qr/Antivirus.*bad.*virus/s,'antivirus events have security classification');
like($s,qr/DMARC.*purple.*dmarc/s,'DMARC events have dedicated classification');
like($s,qr/DKIM.*purple.*dkim/s,'DKIM events have dedicated classification');
like($s,qr/Authentication.*purple.*auth/s,'authentication events have dedicated classification');
like($s,qr/TLS.*teal.*tls/s,'TLS events have dedicated classification');
like($s,qr/Postscreen.*purple.*postscreen/s,'Postscreen events have dedicated classification');
like($s,qr/SMTP.*blue.*smtp/s,'SMTP events have dedicated classification');

like($s,qr/event-reject \.event-dot/,'timeline CSS colors rejection events');
like($s,qr/event-delivery \.event-dot/,'timeline CSS colors delivery events');
like($s,qr/event-filter \.event-dot/,'timeline CSS colors filtering events');
like($s,qr/event-tls \.event-dot/,'timeline CSS colors TLS events');

like($s,qr/timeline_event_html\(\$_\)/,'message detail uses dedicated timeline renderer');

unlike($s,qr/style\s*=\s*["']/i,'timeline introduces no inline styles');
unlike($s,qr/<script\b/i,'timeline introduces no JavaScript');

done_testing;
