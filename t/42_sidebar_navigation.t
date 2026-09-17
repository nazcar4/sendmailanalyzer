use strict; use warnings; use utf8; use Test::More;
my $f='web/sendmailanalyzer.psgi'; open my $fh,'<:encoding(UTF-8)',$f or die $!; local $/; my $s=<$fh>;
for my $route (qw(/messages /direction/inbound /direction/outbound /direction/internal /direction/unknown /senders /recipients /spam /viruses /dsn /rejects /status /auth /tls /rspamd)) {
    like($s,qr/\Q$route\E/,"sidebar/route contains $route");
}
for my $label ('Messaging','Spam','Virus','Notifications / DSN','Rejections and errors','Status / Flow','Authentication','TLS','Rspamd','Senders','Recipients') {
    like($s,qr/\Q$label\E/,"sidebar contains $label");
}
like($s,qr/class="sidebar"/, 'desktop sidebar present');
like($s,qr/mobile-menu/, 'mobile navigation present');
unlike($s,qr/<div class=\?"nav-title\?">Time/, 'time navigation removed from left sidebar');
like($s,qr/m\{\^\/direction\/\(inbound\|outbound\|internal\|relay\|unknown\)\$\}/, 'relay and unknown remain supported direction routes');
done_testing;
