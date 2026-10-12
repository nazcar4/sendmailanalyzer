use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/ip-statistics.sqlite3";
my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

my $d=$s->dbh;

$d->do(
    q{INSERT INTO messages(
        queue_id,first_seen,last_seen,client_ip,direction,rejected,spam_detected
      ) VALUES(?,?,?,?,?,?,?)},
    undef,
    'IPMSG001',
    '2026-10-12T10:00:00+0200',
    '2026-10-12T10:00:01+0200',
    '192.0.2.10',
    'inbound',
    1,
    1
);

$d->do(
    q{INSERT INTO messages(
        queue_id,first_seen,last_seen,client_ip,direction,rejected,spam_detected
      ) VALUES(?,?,?,?,?,?,?)},
    undef,
    'IPMSG002',
    '2026-10-12T10:01:00+0200',
    '2026-10-12T10:01:01+0200',
    '192.0.2.10',
    'outbound',
    0,
    0
);

$d->do(
    q{INSERT INTO messages(
        queue_id,first_seen,last_seen,client_ip,direction
      ) VALUES(?,?,?,?,?)},
    undef,
    'IPMSG003',
    '2026-10-12T10:02:00+0200',
    '2026-10-12T10:02:01+0200',
    '198.51.100.20',
    'inbound'
);

$d->do(
    q{INSERT INTO auth_events(
        timestamp,source,client_ip,success,fingerprint
      ) VALUES(?,?,?,?,?)},
    undef,
    '2026-10-12T10:03:00+0200',
    'dovecot',
    '192.0.2.10',
    1,
    'ipstats-auth-ok'
);

$d->do(
    q{INSERT INTO auth_events(
        timestamp,source,client_ip,success,fingerprint
      ) VALUES(?,?,?,?,?)},
    undef,
    '2026-10-12T10:04:00+0200',
    'dovecot',
    '192.0.2.10',
    0,
    'ipstats-auth-fail'
);

for my $n (1..3) {
    $d->do(
        q{INSERT INTO tls_events(
            timestamp,direction,peer_ip,protocol,fingerprint
          ) VALUES(?,?,?,?,?)},
        undef,
        sprintf('2026-10-12T10:05:%02d+0200',$n),
        'inbound',
        '198.51.100.20',
        'TLSv1.3',
        "ipstats-tls-$n"
    );
}

$d->do(
    q{INSERT INTO tls_events(
        timestamp,direction,peer_ip,protocol,fingerprint
      ) VALUES(?,?,?,?,?)},
    undef,
    '2026-10-12T10:06:00+0200',
    'outbound',
    '192.0.2.10',
    'TLSv1.3',
    'ipstats-tls-main'
);

# Empty IPs must never become ranking entries.
$d->do(
    q{INSERT INTO messages(queue_id,first_seen,last_seen,client_ip)
      VALUES(?,?,?,?)},
    undef,
    'IPMSGEMPTY',
    '2026-10-12T10:07:00+0200',
    '2026-10-12T10:07:01+0200',
    ''
);

my $rows=$s->top_ips(20);

is(scalar(@$rows),2,'only non-empty IP addresses are ranked');

is($rows->[0]{ip},'192.0.2.10','highest combined activity ranks first');
is($rows->[0]{activity},5,'combined activity counts messages, auth and TLS');
is($rows->[0]{messages},2,'message count is aggregated');
is($rows->[0]{rejected},1,'rejected messages are aggregated');
is($rows->[0]{spam},1,'spam messages are aggregated');
is($rows->[0]{inbound},1,'inbound messages are aggregated');
is($rows->[0]{outbound},1,'outbound messages are aggregated');
is($rows->[0]{auth_success},1,'successful authentication is aggregated');
is($rows->[0]{auth_failures},1,'failed authentication is aggregated');
is($rows->[0]{tls_connections},1,'TLS connections are aggregated');
is(
    $rows->[0]{last_activity},
    '2026-10-12T10:06:00+0200',
    'latest activity is merged across data sources'
);

is($rows->[1]{ip},'198.51.100.20','second IP is returned');
is($rows->[1]{activity},4,'second IP combined activity is correct');
is($rows->[1]{messages},1,'second IP message count is correct');
is($rows->[1]{tls_connections},3,'second IP TLS count is correct');

my $limited=$s->top_ips(1);
is(scalar(@$limited),1,'ranking respects requested limit');
is($limited->[0]{ip},'192.0.2.10','limit preserves ranking order');

my $range=$s->top_ips(
    20,
    '2026-10-12T10:04:30+0200',
    '2026-10-12T10:06:30+0200'
);

my %range=map { $_->{ip}=>$_ } @$range;

ok(exists($range{'192.0.2.10'}),'range includes IP with TLS activity');
is($range{'192.0.2.10'}{messages},0,'range excludes earlier messages');
is($range{'192.0.2.10'}{auth_success},0,'range excludes earlier successful auth');
is($range{'192.0.2.10'}{auth_failures},0,'range excludes earlier failed auth');
is($range{'192.0.2.10'}{tls_connections},1,'range includes matching TLS activity');

is($range{'198.51.100.20'}{messages},0,'range excludes second IP earlier message');
is($range{'198.51.100.20'}{tls_connections},3,'range includes second IP TLS activity');

done_testing;
