use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/schema-v9.sqlite3";

sub index_sql {
    my($dbh,$name)=@_;
    my ($sql)=$dbh->selectrow_array(
        q{SELECT sql FROM sqlite_master WHERE type='index' AND name=?},
        undef,$name
    );
    return $sql;
}

my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

my ($schema)=$s->dbh->selectrow_array(
    q{SELECT value FROM meta WHERE key='schema_version'}
);
is($schema,'9','fresh database uses schema v9');

for my $spec (
    ['idx_messages_client_ip','messages','client_ip'],
    ['idx_auth_client_ip','auth_events','client_ip'],
    ['idx_tls_peer_ip','tls_events','peer_ip'],
) {
    my($idx,$table,$column)=@$spec;
    my $sql=index_sql($s->dbh,$idx);

    ok(defined($sql),"$idx exists");
    like($sql,qr/\bON\s+\Q$table\E\s*\(\Q$column\E\)/i,"$idx indexes $table.$column");
    like($sql,qr/\bWHERE\b.*\Q$column\E\s+IS\s+NOT\s+NULL/i,"$idx excludes NULL values");
    like($sql,qr/\Q$column\E\s*<>\s*''/i,"$idx excludes empty values");
}

# Persist representative records before simulating an existing schema-v8 DB.
$s->dbh->do(
    q{INSERT INTO messages(queue_id,first_seen,last_seen,client_ip)
      VALUES(?,?,?,?)},
    undef,'IPV9MSG','2026-10-12T12:00:00','2026-10-12T12:00:01','192.0.2.10'
);

$s->dbh->do(
    q{INSERT INTO auth_events(timestamp,source,client_ip,success,fingerprint)
      VALUES(?,?,?,?,?)},
    undef,'2026-10-12T12:00:00','dovecot','198.51.100.20',0,'ipv9-auth'
);

$s->dbh->do(
    q{INSERT INTO tls_events(timestamp,direction,peer_ip,protocol,fingerprint)
      VALUES(?,?,?,?,?)},
    undef,'2026-10-12T12:00:00','inbound','203.0.113.30','TLSv1.3','ipv9-tls'
);

# Simulate the previous production schema: data exists, v9 indexes do not.
for my $idx (qw(
    idx_messages_client_ip
    idx_auth_client_ip
    idx_tls_peer_ip
)) {
    $s->dbh->do("DROP INDEX $idx");
}
$s->dbh->do(
    q{INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','8')}
);

undef $s;

# Canonical writable open must perform the v8 -> v9 migration in place.
$s=SendmailAnalyzer::Storage::SQLite->new(file=>$db);

($schema)=$s->dbh->selectrow_array(
    q{SELECT value FROM meta WHERE key='schema_version'}
);
is($schema,'9','existing schema v8 database upgrades to v9');

for my $idx (qw(
    idx_messages_client_ip
    idx_auth_client_ip
    idx_tls_peer_ip
)) {
    ok(defined(index_sql($s->dbh,$idx)),"migration recreates $idx");
}

my ($messages)=$s->dbh->selectrow_array(
    q{SELECT COUNT(*) FROM messages WHERE queue_id='IPV9MSG' AND client_ip='192.0.2.10'}
);
is($messages,1,'message data survives v8 to v9 migration');

my ($auth)=$s->dbh->selectrow_array(
    q{SELECT COUNT(*) FROM auth_events WHERE fingerprint='ipv9-auth' AND client_ip='198.51.100.20'}
);
is($auth,1,'authentication data survives v8 to v9 migration');

my ($tls)=$s->dbh->selectrow_array(
    q{SELECT COUNT(*) FROM tls_events WHERE fingerprint='ipv9-tls' AND peer_ip='203.0.113.30'}
);
is($tls,1,'TLS data survives v8 to v9 migration');

done_testing;
