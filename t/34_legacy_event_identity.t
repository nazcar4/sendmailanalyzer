use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use File::Temp qw(tempdir); use File::Path qw(make_path);
use SendmailAnalyzer::LegacyImporter; use SendmailAnalyzer::Storage::SQLite;
{
 package MockStorage;
 sub new { bless {events=>[]},shift }
 sub store_event { my($s,$e)=@_; push @{$s->{events}},$e->as_hash; 1 }
 sub upsert_message { 1 }
 sub store_delivery_recipient { 1 }
}
my $root=tempdir(CLEANUP=>1); my $d="$root/mailhost/2026/09/01"; make_path($d);
open my $fh,'>',"$d/senders.dat" or die $!; print {$fh} "010000:Q1:a\@x:1:1:r\n"; close $fh;
open $fh,'>',"$d/auth.dat" or die $!;
print {$fh} "010001:user:r:PLAIN:SMTP\n010001:user:r:PLAIN:SMTP\n";
close $fh;
my $st=MockStorage->new; SendmailAnalyzer::LegacyImporter->new(storage=>$st)->import_tree($root);
my @auth=grep { $_->{type} eq 'smtp_auth' } @{$st->{events}};
is(scalar @auth,2,'duplicate legacy auth lines are both represented');
isnt($auth[0]{legacy_locator},$auth[1]{legacy_locator},'duplicate lines receive distinct deterministic locators');
like($auth[0]{legacy_locator},qr{/auth\.dat:1\z},'first line locator includes line number');
like($auth[1]{legacy_locator},qr{/auth\.dat:2\z},'second line locator includes line number');
my $fake=bless {},'SendmailAnalyzer::Storage::SQLite';
my %base=(timestamp=>'2026-09-01T01:00:01',host=>'mailhost',source=>'legacy',type=>'smtp_auth',raw=>'same');
my $f1=$fake->_fingerprint({%base,legacy_locator=>'mailhost/2026/09/01/auth.dat:1'});
my $f2=$fake->_fingerprint({%base,legacy_locator=>'mailhost/2026/09/01/auth.dat:2'});
my $f1b=$fake->_fingerprint({%base,legacy_locator=>'mailhost/2026/09/01/auth.dat:1'});
isnt($f1,$f2,'legacy locator participates in event fingerprint');
is($f1,$f1b,'same legacy locator remains idempotent');
done_testing;
