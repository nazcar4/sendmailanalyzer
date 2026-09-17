use strict;
use warnings;
use utf8;
use Test::More;
use Encode qw(decode encode);
use JSON::PP qw(encode_json decode_json);
use FindBin qw($Bin);

my $root = "$Bin/..";
for my $f (qw(lib/SendmailAnalyzer/Storage/SQLite.pm web/sendmailanalyzer.psgi)) {
    open my $fh, '<:encoding(UTF-8)', "$root/$f" or die $!;
    local $/; my $s=<$fh>;
    like($s, qr/use utf8;/, "$f declares UTF-8 source semantics");
    unlike($s, qr/(?:Ã.|Â.|â€)/, "$f contains no common UTF-8 mojibake");
}
my $label='résumé';
my $json=encode_json({sender=>$label});
my $round=decode_json($json);
is($round->{sender},$label,'JSON::PP round-trips UTF-8 label');
is($json, encode('UTF-8', '{"sender":"résumé"}'), 'JSON output is correctly UTF-8 encoded');
done_testing;
