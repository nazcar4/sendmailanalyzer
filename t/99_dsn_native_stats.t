use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;

use lib "$FindBin::Bin/../lib";

BEGIN {
    eval {
        require DBI;
        require DBD::SQLite;
        1;
    } or plan skip_all => 'DBI/SQLite unavailable';
}

use SendmailAnalyzer::Storage::SQLite;
use SendmailAnalyzer::LegacyImporter;

my $tmp=tempdir(CLEANUP=>1);
my $db="$tmp/dsn.sqlite";

my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);
my $dbh=$s->dbh;

my @recipients=(
    ['Q1','a@example.test','sent',    '2.0.0','local','2026-10-16T10:00:00'],
    ['Q2','b@example.test','sent',    '2.0.0','local','2026-10-16T10:01:00'],
    ['Q3','c@example.test','deferred','4.3.0','smtp', '2026-10-16T10:02:00'],
    ['Q4','d@example.test','bounced', '5.1.1','smtp', '2026-10-16T10:03:00'],
    ['Q5','e@example.test','sent',    '2.0.0','local','2026-10-15T23:59:00'],
    ['Q6','f@example.test','sent',    '',     'local','2026-10-16T10:04:00'],
);

for my $r (@recipients) {
    $dbh->do(
        q{
            INSERT INTO recipients(
                queue_id,recipient,status,dsn,relay,timestamp
            )
            VALUES(?,?,?,?,?,?)
        },
        undef,
        @$r
    );
}

$dbh->do(
    q{
        INSERT INTO events(
            fingerprint,timestamp,host,queue_id,message_id,
            source,type,data_json,raw
        )
        VALUES(?,?,?,?,?,?,?,?,?)
    },
    undef,
    'legacy-dsn-event',
    '2026-10-16T11:00:00',
    'mail.example.test',
    'QL1',
    undef,
    'legacy',
    'dsn',
    '{"status":"legacy-event"}',
    'legacy explicit dsn'
);

$dbh->do(
    q{
        INSERT INTO legacy_aggregates(
            day,hour,metric,detail,count
        )
        VALUES(?,?,?,?,?)
    },
    undef,
    '2026-10-16',
    '10',
    'dsn_events',
    'legacy-aggregate',
    2
);

my $all=$s->stats();

is(
    $all->{dsn_events},
    8,
    'cumulative DSN count includes native recipients, explicit legacy events and legacy aggregates'
);

my $day=$s->stats_range(
    '2026-10-16T00:00:00',
    '2026-10-16T23:59:59'
);

is(
    $day->{dsn_events},
    7,
    'period DSN count filters native recipient timestamps correctly'
);

my $before=$s->stats_range(
    '2026-10-15T00:00:00',
    '2026-10-15T23:59:59'
);

is(
    $before->{dsn_events},
    1,
    'native DSN outside selected day remains outside range'
);

my $hour10=$s->stats_range(
    '2026-10-16T10:00:00',
    '2026-10-16T10:59:59.999999'
);

is(
    $hour10->{dsn_events},
    6,
    'hourly DSN total uses only matching-hour legacy aggregate'
);

my $hour10_rows=$s->dsn_stats(
    '2026-10-16T10:00:00',
    '2026-10-16T10:59:59.999999'
);

my $hour10_sum=0;
$hour10_sum += $_->{count} for @$hour10_rows;

is(
    $hour10_sum,
    6,
    'hourly dsn_stats includes only matching-hour legacy aggregate'
);

my $hour11_rows=$s->dsn_stats(
    '2026-10-16T11:00:00',
    '2026-10-16T11:59:59.999999'
);

my $hour11_sum=0;
$hour11_sum += $_->{count} for @$hour11_rows;

is(
    $hour11_sum,
    1,
    'hourly dsn_stats excludes legacy aggregates belonging to another hour'
);

my $rows=$s->dsn_stats();
my %count=map {
    ($_->{status} => 0+$_->{count})
} @$rows;

is($count{'2.0.0'},3,'native successful DSN codes are grouped');
is($count{'4.3.0'},1,'native temporary DSN codes are grouped');
is($count{'5.1.1'},1,'native permanent DSN codes are grouped');
is($count{'legacy-event'},1,'explicit legacy DSN event remains visible');
is($count{'legacy-aggregate'},2,'legacy aggregate DSN remains visible');

ok(
    !exists $count{''},
    'empty DSN values are excluded'
);

my $day_rows=$s->dsn_stats(
    '2026-10-16T00:00:00',
    '2026-10-16T23:59:59'
);

my %day_count=map {
    ($_->{status} => 0+$_->{count})
} @$day_rows;

is(
    $day_count{'2.0.0'}||0,
    2,
    'bounded dsn_stats excludes native DSN records outside selected day'
);

is(
    $day_count{'legacy-event'}||0,
    1,
    'bounded dsn_stats keeps explicit legacy DSN inside selected day'
);

is(
    $day_count{'legacy-aggregate'}||0,
    2,
    'bounded dsn_stats keeps bounded legacy aggregate inside selected day'
);

my $day_sum=0;
$day_sum += $_->{count} for @$day_rows;

is(
    $day_sum,
    $day->{dsn_events},
    'bounded dsn_stats agrees with selected-day DSN total'
);

my $before_rows=$s->dsn_stats(
    '2026-10-15T00:00:00',
    '2026-10-15T23:59:59'
);

my %before_count=map {
    ($_->{status} => 0+$_->{count})
} @$before_rows;

is(
    $before_count{'2.0.0'}||0,
    1,
    'bounded dsn_stats returns the previous-day native DSN independently'
);

my $sum=0;
$sum += $_->{count} for @$rows;

is(
    $sum,
    $all->{dsn_events},
    'dsn_stats total agrees with cumulative dsn_events'
);

open my $fh,'<',"$FindBin::Bin/../web/sendmailanalyzer.psgi"
    or die $!;

my $web;
{
    local $/;
    $web=<$fh>;
}
close $fh;

like(
    $web,
    qr/Success 2\.x\.x/,
    'DSN page exposes successful enhanced-status group'
);

like(
    $web,
    qr/Temporary 4\.x\.x/,
    'DSN page exposes temporary-failure group'
);

like(
    $web,
    qr/Permanent 5\.x\.x/,
    'DSN page exposes permanent-failure group'
);

like(
    $web,
    qr/'DSN code',\s*'Meaning',\s*'Total',\s*'Share'/s,
    'DSN table exposes code, meaning, total and share columns'
);

like(
    $web,
    qr/Delivery status \/ DSN/,
    'DSN page uses delivery-status terminology'
);


# Legacy DSN records must use exactly one storage path:
# real Queue-IDs become explicit events, while upstream synthetic
# FaKe*/NOQUEUE identifiers become bounded legacy aggregates.
my $legacy_root="$tmp/legacy";
my $legacy_day="$legacy_root/mailhost/2026/10/16";

make_path($legacy_day);

open my $dsn_fh,'>',"$legacy_day/dsn.dat"
    or die "$legacy_day/dsn.dat: $!";

print {$dsn_fh}
    "120000:QREAL01:SRCREAL:Delivered\n",
    "120001:FaKeDSN001:SRCFAKE:Bounced\n";

close $dsn_fh;

my $legacy_db="$tmp/legacy.sqlite";
my $legacy_store=SendmailAnalyzer::Storage::SQLite->new(
    file=>$legacy_db
);

my $legacy_result=
    SendmailAnalyzer::LegacyImporter->new(
        storage=>$legacy_store
    )->import_tree($legacy_root);

my $explicit_legacy_dsn=
    $legacy_store->dbh->selectrow_array(
        q{
            SELECT COUNT(*)
            FROM events
            WHERE type='dsn'
        }
    );

my $synthetic_legacy_dsn=
    $legacy_store->dbh->selectrow_array(
        q{
            SELECT COALESCE(SUM(count),0)
            FROM legacy_aggregates
            WHERE metric='dsn_events'
        }
    );

is(
    $explicit_legacy_dsn,
    1,
    'real legacy DSN Queue-ID is stored exactly once as an explicit event'
);

is(
    $synthetic_legacy_dsn,
    1,
    'synthetic FaKe legacy DSN is stored exactly once as an aggregate'
);

is(
    $legacy_result->{synthetic_skipped},
    1,
    'synthetic legacy DSN is deliberately skipped as an individual event'
);

my $legacy_stats=$legacy_store->stats();

is(
    $legacy_stats->{dsn_events},
    2,
    'legacy real plus synthetic DSN records total two without double counting'
);

my %legacy_dsn_stats=map {
    ($_->{status} => 0+$_->{count})
} @{$legacy_store->dsn_stats()};

is(
    $legacy_dsn_stats{'Delivered'},
    1,
    'real legacy DSN status remains visible'
);

is(
    $legacy_dsn_stats{'Bounced'},
    1,
    'synthetic legacy DSN status remains visible'
);


like(
    $web,
    qr/sub dsn_visual_donut/,
    'DSN page has a server-side distribution donut'
);

like(
    $web,
    qr/sub dsn_code_ranking/,
    'DSN page has a visual code ranking'
);

like(
    $web,
    qr/Delivery health/,
    'DSN page exposes a delivery-health visual summary'
);

like(
    $web,
    qr/Most frequent codes/,
    'DSN page exposes the most frequent DSN codes'
);

like(
    $web,
    qr/Legacy \/ other/,
    'DSN visualisation keeps legacy and non-standard states explicit'
);

done_testing();
