use strict; use warnings; use utf8;
use Test::More;
use FindBin qw($Bin);

my $web="$Bin/../web/sendmailanalyzer.psgi";
open my $fh,'<:encoding(UTF-8)',$web or die $!; local $/; my $s=<$fh>; close $fh;

like($s,qr/sub period_chart/,'dashboard has server-side period chart renderer');
like($s,qr/class="bigchart"/,'dashboard renders large SVG activity chart');
like($s,qr/sub segmented_meter/,'dashboard has distribution meter renderer');
like($s,qr/sub mini_bar/,'dashboard has proportional mini bars');
like($s,qr/Daily Report/,'dashboard has classic daily report heading');
like($s,qr/Message Flow/,'dashboard exposes classic messaging-flow summary');
like($s,qr/Message Distribution/,'dashboard includes direction/status distribution');
like($s,qr/Senders/,'navigation includes sender ranking');
like($s,qr/Recipients/,'navigation includes recipient ranking');
like($s,qr/Timeline/,'message detail uses a correlated timeline');
like($s,qr/Security overview/,'security section has overview');
like($s,qr/Forced actions/,'Rspamd page visualizes native forced actions');
like($s,qr/class="sidebar"/,'redesign has fixed left sidebar');
unlike($s,qr/style\s*=\s*["']/i,'redesign keeps inline styles out of generated HTML');
unlike($s,qr/<script\b/i,'redesign requires no JavaScript');
like($s,qr/HTTP_X_FORWARDED_PREFIX/,'redesign preserves reverse proxy prefix support');

my $storage="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm";
open my $sf,'<:encoding(UTF-8)',$storage or die $!; local $/; my $ss=<$sf>; close $sf;
like($ss,qr/direction='relay'.*relay/s,'stats includes relay direction for visual distribution');

done_testing;
