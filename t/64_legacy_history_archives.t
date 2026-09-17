use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use SendmailAnalyzer::LegacySource;
use SendmailAnalyzer::LegacyImporter;
use SendmailAnalyzer::MigrationPreflight;
use SendmailAnalyzer::MigrationAudit;

{
    package MockStorage;
    sub new { bless { events=>[], messages=>[], rcpt=>[] }, shift }
    sub store_event { my ($s,$e)=@_; push @{$s->{events}}, $e->as_hash; 1 }
    sub upsert_message { my ($s,$m)=@_; push @{$s->{messages}}, {%$m}; 1 }
    sub store_delivery_recipient { my ($s,$e)=@_; push @{$s->{rcpt}}, {%$e}; 1 }
}

my $root=tempdir(CLEANUP=>1);
my $month="$root/mailhost/2026/08";
my $arcsrc="$root/archive-src";
make_path("$arcsrc/01","$arcsrc/02","$month/01","$root/mailhost/2026/09/01");

# The archive contains an older copy of 08/01/senders.dat.  A live/direct .dat
# for the same day/type must win, while other archived file types remain usable.
open my $fh,'>',"$arcsrc/01/senders.dat" or die $!;
print {$fh} "010000:QARCH1:old\@example.net:10:1:old-relay:\n";
close $fh;
open $fh,'>',"$arcsrc/01/recipient.dat" or die $!;
print {$fh} "010100:QACTIVE:dest\@example.net:mx.example.net:Sent\n";
close $fh;
open $fh,'>',"$arcsrc/02/senders.dat" or die $!;
print {$fh} "020000:QARCH2:archive\@example.net:20:1:archive-relay:\n";
close $fh;
open $fh,'>',"$arcsrc/02/recipient.dat" or die $!;
print {$fh} "020100:QARCH2:dest2\@example.net:mx2.example.net:Sent\n";
close $fh;

is(system('tar','-czf',"$month/history.tar.gz",'-C',$arcsrc,'01','02'),0,'created representative 9.4 history.tar.gz');
remove_tree($arcsrc);

open $fh,'>',"$month/01/senders.dat" or die $!;
print {$fh} "010000:QACTIVE:active\@example.net:30:1:active-relay:\n";
close $fh;
open $fh,'>',"$root/mailhost/2026/09/01/senders.dat" or die $!;
print {$fh} "030000:QSEP:sep\@example.net:40:1:sep-relay:\n";
close $fh;

my $source=SendmailAnalyzer::LegacySource->new(root=>$root);
is($source->archives,1,'one monthly history archive discovered');
my $senders=$source->entries(type=>'senders');
is(scalar(@$senders),3,'senders include archived and active historical days');
is(scalar(grep { $_->{kind} eq 'archive' } @$senders),1,'only non-shadowed archived senders entry is used');
my ($aug1)=grep { $_->{date} eq '2026-08-01' } @$senders;
is($aug1->{kind},'file','active .dat overrides same archived day/type');
is($aug1->{locator},'mailhost/2026/08/01/senders.dat','normalized locator is independent of physical source');

my $pre=SendmailAnalyzer::MigrationPreflight->scan(root=>$root);
is($pre->{history_archives},1,'preflight includes monthly history archive');
is($pre->{archived_sender_files},1,'preflight counts archived sender files actually selected');
is($pre->{sender_files},3,'preflight covers all historical sender days');
is($pre->{min_date},'2026-08-01','preflight minimum date includes archive');
is($pre->{max_date},'2026-09-01','preflight maximum date includes active data');
is($pre->{duplicate_queue_ids},0,'no false Queue-ID duplicates across archive/direct shadowing');

my $st=MockStorage->new;
my $imp=SendmailAnalyzer::LegacyImporter->new(storage=>$st);
my $r=$imp->import_tree($root);
is($r->{archives},1,'importer reports archive inventory');
is($r->{archive_extractions},1,'monthly history archive is extracted once for the complete import');
ok($r->{archived_files}>=3,'importer consumes archived non-shadowed data files');
my %qid=map { (($_->{queue_id}||'') => 1) } @{$st->{events}};
ok($qid{QACTIVE},'active August message imported');
ok($qid{QARCH2},'archived August message imported');
ok($qid{QSEP},'September active message imported');
ok(!$qid{QARCH1},'shadowed archived sender row was not imported');

my $days=SendmailAnalyzer::MigrationAudit->discover_days($root);
is_deeply([map { $_->{date} } @$days],[qw(2026-08-01 2026-08-02 2026-09-01)],'audit discovers archived and active days in chronological order');
my ($d2)=grep { $_->{date} eq '2026-08-02' } @$days;
my $cnt=SendmailAnalyzer::MigrationAudit->legacy_counts($d2);
is($cnt->{messages},1,'audit counts archived message evidence');
is($cnt->{recipients},1,'audit counts archived recipient evidence');
is($cnt->{sent},1,'audit counts archived sent delivery evidence');

done_testing;
