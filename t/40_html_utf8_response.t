use strict; use warnings; use utf8;
use Test::More;
use Encode qw(encode decode FB_CROAK);
use FindBin qw($Bin);

my $psgi="$Bin/../web/sendmailanalyzer.psgi";
open my $fh,'<:raw',$psgi or die $!;
local $/; my $src=<$fh>; close $fh;
my $text=decode('UTF-8',$src,FB_CROAK);

like($text, qr/use Encode qw\(encode_utf8\);/, 'PSGI imports encode_utf8');
like($text, qr/sub html_response \{.*encode_utf8\(\$html\)/s, 'HTML response helper emits UTF-8 octets');
unlike($text, qr/return \[\s*(?:200|404)\s*,\s*headers\('text\/html; charset=utf-8'\)/, 'HTML routes do not return character strings directly');

my $html="<title>SendmailAnalyzer 10 · résumé · naïve · café · historical</title>";
my $bytes=encode('UTF-8',$html);
my $decoded=decode('UTF-8',$bytes,FB_CROAK);
is($decoded,$html,'representative HTML literals round-trip as strict UTF-8');
is(unpack('H*',encode('UTF-8','·')),'c2b7','middle dot is encoded as C2 B7');

done_testing;
