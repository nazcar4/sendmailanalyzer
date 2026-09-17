use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use FindBin;
use lib "$FindBin::Bin/../lib"; BEGIN { eval { require DBI; require DBD::SQLite; 1 } or plan skip_all => 'DBI/SQLite unavailable'; } use SendmailAnalyzer::Storage::SQLite; use SendmailAnalyzer::LegacyImporter;
my $tmp=tempdir(CLEANUP=>1); for my $d (qw(12 13)) { my $dir="$tmp/mailhost/2026/09/$d"; make_path($dir); open my $f,'>',"$dir/senders.dat" or die $!; print $f "120000:Q$d:a\@example.net:100:1:mx[$d]\n"; close $f; }
my $db="$tmp/x.sqlite"; my $s=SendmailAnalyzer::Storage::SQLite->new(file=>$db); my $r=SendmailAnalyzer::LegacyImporter->new(storage=>$s)->import_tree($tmp,until=>'2026-09-12'); is($r->{files},1,'only legacy files through cutoff imported');
my ($n)=$s->dbh->selectrow_array('SELECT COUNT(*) FROM messages'); is($n,1,'one cutoff message'); my ($q)=$s->dbh->selectrow_array('SELECT queue_id FROM messages'); is($q,'Q12','later day excluded');
done_testing;
