use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/timeline-duration.sqlite3";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

$s->dbh->do(
    q{INSERT INTO messages(queue_id,first_seen,last_seen,sender,direction)
      VALUES(?,?,?,?,?)},
    undef,
    'TIMEDELTA001',
    '2026-10-12T12:00:00+0200',
    '2026-10-12T12:00:02+0200',
    'sender@example.test',
    'inbound'
);

my @events=(
    ['td-1','2026-10-12T10:00:00.350Z','second'],
    ['td-2','2026-10-12T12:00:01.850+0200','third'],
    ['td-3','2026-10-12T12:00:00.100+0200','first'],
);

for my $e (@events) {
    $s->dbh->do(
        q{INSERT INTO events(
            fingerprint,timestamp,host,queue_id,message_id,
            source,type,data_json,raw
          ) VALUES(?,?,?,?,?,?,?,?,?)},
        undef,
        $e->[0],
        $e->[1],
        'mailhost',
        'TIMEDELTA001',
        'timeline@example.test',
        'postfix',
        $e->[2],
        '{}',
        'synthetic duration fixture'
    );
}

my $m=$s->message_detail('TIMEDELTA001');

is_deeply(
    [map { $_->{type} } @{$m->{events}}],
    [qw(first second third)],
    'timeline orders mixed timezone formats by absolute instant'
);

ok(
    !defined($m->{events}[0]{delta_seconds}),
    'first timeline event has no delta'
);

cmp_ok(
    abs($m->{events}[1]{delta_seconds}-0.25),
    '<',
    0.0001,
    'fractional 250 ms delta is preserved'
);

cmp_ok(
    abs($m->{events}[2]{delta_seconds}-1.5),
    '<',
    0.0001,
    'fractional 1.5 second delta is preserved'
);

my $web="$Bin/../web/sendmailanalyzer.psgi";
open my $fh,'<:encoding(UTF-8)',$web or die $!;
local $/;
my $source=<$fh>;
close $fh;

like($source,qr/sub timeline_delta_text/,'web has timeline delta formatter');
like($source,qr/event-delta/,'timeline renders elapsed-time marker');
like($source,qr/\+.*ms/,'timeline supports millisecond display');
like($source,qr/\+.*s/,'timeline supports second display');

done_testing;
