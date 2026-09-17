use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use File::Temp qw(tempdir); use File::Path qw(make_path); use SendmailAnalyzer::LegacyImporter; use SendmailAnalyzer::MigrationPreflight; use SendmailAnalyzer::MigrationAudit;
{
 package MockStorage;
 sub new { bless {events=>[],messages=>[],rcpt=>[],agg=>{}},shift }
 sub store_event { my($s,$e)=@_; push @{$s->{events}},$e->as_hash; 1 }
 sub upsert_message { my($s,$m)=@_; push @{$s->{messages}},{%$m}; 1 }
 sub store_delivery_recipient { my($s,$e)=@_; push @{$s->{rcpt}},{%$e}; 1 }
 sub set_legacy_aggregate { my($s,$d,$h,$m,$detail,$n)=@_; $s->{agg}{join('|',$d,$h,$m,$detail)}=$n; $n }
}
my $root=tempdir(CLEANUP=>1); my $d="$root/mailhost/2026/06/26"; make_path($d);
open my $fh,'>',"$d/senders.dat" or die $!; print {$fh} "120000:REAL123:a\@example.net:100:1:mx:\n120000:FaKeSender123:blocked\@example.net:0:0:bad:\n"; close $fh;
open $fh,'>',"$d/recipient.dat" or die $!; print {$fh} "120001:REAL123:b\@example.net:mx:Sent\n120002:FaKeRCPT:b\@example.net:mx:Sent\n"; close $fh;
open $fh,'>',"$d/rejected.dat" or die $!; print {$fh} "120003:FaKeNn4zIOpFBpjijQZy:check_relay:bad.example:a\@bad.example:blocked using dnsbl\n120004:REAL123:cleanup:mx:a\@example.net:rejected after queue\n"; close $fh;
my $pre=SendmailAnalyzer::MigrationPreflight->scan(root=>$root);
is($pre->{sender_rows},2,'preflight sees both raw sender rows');
is($pre->{synthetic_sender_rows},1,'preflight classifies upstream FaKe sender identity as synthetic');
is($pre->{real_sender_rows},1,'preflight counts only one real queued message');
my ($day)=@{SendmailAnalyzer::MigrationAudit->discover_days($root)};
my $lc=SendmailAnalyzer::MigrationAudit->legacy_counts($day);
is($lc->{messages},1,'migration audit excludes FaKe sender rows from message truth');
my $st=MockStorage->new; my $r=SendmailAnalyzer::LegacyImporter->new(storage=>$st)->import_tree($root);
my @real=grep { ($_->{queue_id}||'') eq 'REAL123' } @{$st->{messages}};
my @fake=grep { ($_->{queue_id}||'') =~ /^FaKe/ } @{$st->{messages}};
ok(@real>=1,'real senders.dat message is stored');
is(scalar @fake,0,'synthetic FaKe identifiers never create message rows');
is(scalar @{$st->{rcpt}},1,'orphan synthetic recipient is not normalized into recipients table');
my @synth_events=grep { (($_->{queue_id}||'') =~ /^FaKe/) || (($_->{legacy_queue_id}||'') =~ /^FaKe/) } @{$st->{events}};
is(scalar @synth_events,0,'synthetic legacy identities are not materialized as individual events');
my $agg_rej=0; $agg_rej+=$st->{agg}{$_} for grep { /\|smtp_rejected\|/ } keys %{$st->{agg}};
is($agg_rej,1,'synthetic rejection is preserved as a bounded historical aggregate');
my $agg_sent=0; $agg_sent+=$st->{agg}{$_} for grep { /\|delivery_sent\|/ } keys %{$st->{agg}};
is($agg_sent,1,'synthetic recipient delivery is preserved as an aggregate');
is($r->{messages},1,'message counter excludes synthetic FaKe rows even when they are in senders.dat');
ok(($r->{synthetic_skipped}||0)>=3,'synthetic sender/recipient/reject identities are aggregated instead of materialized');
done_testing;
