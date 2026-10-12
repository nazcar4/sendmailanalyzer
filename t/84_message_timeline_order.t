use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/timeline.sqlite3";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

$s->dbh->do(
    q{INSERT INTO messages(queue_id,first_seen,last_seen,sender,direction)
      VALUES(?,?,?,?,?)},
    undef,
    'TIMELINE001',
    '2026-10-12T12:00:00',
    '2026-10-12T12:00:04',
    'sender@example.test',
    'inbound'
);

my @events=(
    ['tl-1','2026-10-12T12:00:03','delivery'],
    ['tl-2','2026-10-12T12:00:01','connect'],
    ['tl-3','2026-10-12T12:00:02','filter_a'],
    ['tl-4','2026-10-12T12:00:02','filter_b'],
    ['tl-5',undef,'no_timestamp'],
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
        'TIMELINE001',
        'timeline@example.test',
        'postfix',
        $e->[2],
        '{}',
        'synthetic timeline fixture'
    );
}

my $m=$s->message_detail('TIMELINE001');
ok($m,'message detail is available');

is_deeply(
    [map { $_->{type} } @{$m->{events}}],
    [qw(connect filter_a filter_b delivery no_timestamp)],
    'timeline is chronological, stable for equal timestamps, and puts missing timestamps last'
);

is(
    $m->{events}[0]{timestamp},
    '2026-10-12T12:00:01',
    'earliest timestamp is first'
);

is(
    $m->{events}[3]{timestamp},
    '2026-10-12T12:00:03',
    'latest timestamped event appears after intermediate events'
);

ok(
    !defined($m->{events}[4]{timestamp}),
    'event without timestamp is placed at the end'
);

is(
    $m->{events}[1]{type},
    'filter_a',
    'first equal-timestamp event keeps insertion order'
);

is(
    $m->{events}[2]{type},
    'filter_b',
    'second equal-timestamp event keeps insertion order'
);

done_testing;
