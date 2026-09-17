use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use Fcntl qw(SEEK_CUR);

my ($fh,$path)=tempfile();
print {$fh} "first\n";
close $fh;
open my $r,'<',$path or die $!;
is(scalar(<$r>), "first\n", 'initial line read');
ok(!defined(<$r>), 'reader reaches EOF');
open my $a,'>>',$path or die $!;
print {$a} "second\n";
close $a;
ok(!defined(<$r>), 'EOF remains sticky before refresh');
ok(seek($r,0,SEEK_CUR), 'no-op seek clears EOF without changing position');
is(scalar(<$r>), "second\n", 'appended line is read after EOF refresh');
close $r;

open my $src,'<','bin/sa10_collect' or die $!;
local $/; my $text=<$src>; close $src;
like($text, qr/use Fcntl qw\(SEEK_SET SEEK_CUR\)/, 'collector imports SEEK_CUR');
like($text, qr/seek\(\$fh,0,SEEK_CUR\).*Cannot refresh EOF state/s, 'collector refreshes EOF in follow loop');
done_testing();
