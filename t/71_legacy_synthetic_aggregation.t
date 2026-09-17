use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use SendmailAnalyzer::LegacyImporter;

{
    package AggStorage;
    sub new { bless {events=>0,messages=>0,agg=>{},agg_writes=>0},shift }
    sub store_event { $_[0]{events}++; 1 }
    sub upsert_message { $_[0]{messages}++; 1 }
    sub store_delivery_recipient { 1 }
    sub set_legacy_aggregate {
        my($s,$d,$h,$m,$detail,$n)=@_;
        $s->{agg}{join('|',$d,$h,$m,$detail)}=$n;
        $s->{agg_writes}++;
        return $n;
    }
}

my $root=tempdir(CLEANUP=>1); my $d="$root/mailhost/2026/06/26"; make_path($d);
open my $s,'>',"$d/senders.dat" or die $!;
open my $r,'>',"$d/rejected.dat" or die $!;
for my $i (1..100_000) {
    my $id=sprintf('FaKe%016d',$i);
    print {$s} "120000:$id:blocked\@example.net:0:0:bad:\n";
    print {$r} "120001:$id:check_relay:bad.example:blocked\@example.net:blocked using dnsbl.example\n";
}
close $s; close $r;
my $st=AggStorage->new;
my $out=SendmailAnalyzer::LegacyImporter->new(storage=>$st)->import_tree($root);
is($st->{events},0,'100k synthetic rejects create zero individual events');
is($st->{messages},0,'100k synthetic envelopes create zero message rows');
ok($st->{agg_writes} < 20,'synthetic history flushes only a bounded number of aggregate rows');
is($out->{synthetic_skipped},200_000,'all synthetic sender/reject identities counted as aggregated');
my $smtp=0; $smtp += $st->{agg}{$_} for grep {/\|smtp_rejected\|/} keys %{$st->{agg}};
is($smtp,100_000,'all synthetic SMTP rejects retained in aggregate count');
my $env=0; $env += $st->{agg}{$_} for grep {/\|synthetic_envelope\|/} keys %{$st->{agg}};
is($env,100_000,'all synthetic envelope identities retained only as aggregate count');
done_testing;
