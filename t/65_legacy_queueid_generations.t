use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use File::Temp qw(tempdir); use File::Path qw(make_path);
use SendmailAnalyzer::LegacyImporter; use SendmailAnalyzer::LegacyIdentity; use SendmailAnalyzer::LegacySource;

{
 package MockStorage;
 sub new { bless {events=>[],messages=>[],recipients=>[]},shift }
 sub store_event { my($s,$e)=@_; push @{$s->{events}},$e->as_hash; 1 }
 sub upsert_message { my($s,$m)=@_; push @{$s->{messages}},{%$m}; 1 }
 sub store_delivery_recipient { my($s,$e)=@_; push @{$s->{recipients}},{%$e}; 1 }
}
my $root=tempdir(CLEANUP=>1);
for my $date (qw(01 02)) {
    my $d="$root/mailhost/2026/08/$date"; make_path($d);
    open my $fh,'>',"$d/senders.dat" or die $!;
    print {$fh} ($date eq '01' ? "010000:ABC123:first\@example:10:1:r1\n" : "020000:ABC123:second\@example:20:1:r2\n");
    close $fh;
    open $fh,'>',"$d/recipient.dat" or die $!;
    print {$fh} ($date eq '01' ? "010001:ABC123:a\@example:r1:Sent\n" : "020001:ABC123:b\@example:r2:Sent\n");
    close $fh;
}
my $st=MockStorage->new;
my $r=SendmailAnalyzer::LegacyImporter->new(storage=>$st)->import_tree($root);
my @env=grep { $_->{type} eq 'envelope' } @{$st->{events}};
is(scalar @env,2,'both reused Queue-ID generations imported');
is($env[0]{queue_id},'ABC123','first generation keeps original internal key when no native row exists');
like($env[1]{queue_id},qr/^ABC123__L20260802_[0-9a-f]{12}$/,'later reused generation gets stable internal key');
is($env[1]{legacy_queue_id},'ABC123','event preserves original Queue-ID');
my @msgs=grep { ($_->{sender}||'') ne '' } @{$st->{messages}};
is(scalar @msgs,2,'both messages remain distinct');
is($msgs[1]{display_queue_id},'ABC123','synthetic generation preserves display Queue-ID');
isnt($msgs[0]{queue_id},$msgs[1]{queue_id},'internal message identities are distinct');
is($st->{recipients}[1]{queue_id},$msgs[1]{queue_id},'recipient follows the same internal generation key');

{
 package FakeDBH;
 sub new { bless {date=>$_[1]},shift }
 sub selectrow_array { return $_[0]{date}.'T03:00:00' }
 package FakeStorage;
 sub new { bless {dbh=>FakeDBH->new($_[1])},shift }
 sub dbh { $_[0]{dbh} }
}
my $source=SendmailAnalyzer::LegacySource->new(root=>$root);
my $id=SendmailAnalyzer::LegacyIdentity->new(source=>$source,storage=>FakeStorage->new('2026-08-02'));
like($id->internal_qid('mailhost','2026-08-01','ABC123'),qr/^ABC123__L20260801_/,'older legacy generation is qualified when native v10 owns same Queue-ID on another day');
is($id->internal_qid('mailhost','2026-08-02','ABC123'),'ABC123','matching native-v10 date keeps canonical Queue-ID for merge');
is($id->reused_queue_ids,1,'reuse counter reports one Queue-ID');
ok($id->synthetic_generations>=1,'synthetic generation count reported');
done_testing;
