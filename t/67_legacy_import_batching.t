use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use SendmailAnalyzer::LegacyImporter;

{
    package TxDBH;
    sub new { bless { AutoCommit=>1,begin=>0,commit=>0,rollback=>0 }, shift }
    sub begin_work { my ($s)=@_; die "transaction already active" if !$s->{AutoCommit}; $s->{AutoCommit}=0; $s->{begin}++; 1 }
    sub commit { my ($s)=@_; die "no transaction" if $s->{AutoCommit}; $s->{AutoCommit}=1; $s->{commit}++; 1 }
    sub rollback { my ($s)=@_; $s->{AutoCommit}=1; $s->{rollback}++; 1 }
}
{
    package TxStorage;
    sub new { my ($class,%o)=@_; bless { dbh=>TxDBH->new, fail_date=>$o{fail_date}, events=>[], messages=>[], rcpt=>[] },$class }
    sub dbh { shift->{dbh} }
    sub store_event { my ($s,$e)=@_; my $h=$e->as_hash; die "forced day failure\n" if $s->{fail_date} && ($h->{timestamp}||'') =~ /^\Q$s->{fail_date}\E/; push @{$s->{events}},$h; 1 }
    sub upsert_message { my ($s,$m)=@_; push @{$s->{messages}},{%$m}; 1 }
    sub store_delivery_recipient { my ($s,$e)=@_; push @{$s->{rcpt}},{%$e}; 1 }
}

my $root=tempdir(CLEANUP=>1);
for my $day (qw(01 02)) {
    my $dir="$root/mailhost/2026/08/$day"; make_path($dir);
    open my $fh,'>',"$dir/senders.dat" or die $!;
    print {$fh} sprintf("010000:Q%s:sender%s\@example.net:100:1:relay:\n",$day,$day);
    close $fh;
}

my @progress;
my $st=TxStorage->new;
my $r=SendmailAnalyzer::LegacyImporter->new(storage=>$st)->import_tree($root,progress=>sub { push @progress,$_[0] });
is($st->dbh->{begin},2,'one transaction begins per legacy day');
is($st->dbh->{commit},2,'one transaction commits per legacy day');
is($st->dbh->{rollback},0,'successful import does not roll back');
is(scalar(grep {/day 1\/2 .*2026-08-01 committed/} @progress),1,'progress reports first committed day');
is(scalar(grep {/day 2\/2 .*2026-08-02 committed/} @progress),1,'progress reports second committed day');
is($r->{messages},2,'both daily messages imported');

my $bad=TxStorage->new(fail_date=>'2026-08-02');
my $ok=eval { SendmailAnalyzer::LegacyImporter->new(storage=>$bad)->import_tree($root); 1 };
ok(!$ok,'second-day failure propagates');
is($bad->dbh->{begin},2,'failed run begins first and second day transactions');
is($bad->dbh->{commit},1,'first day is committed before second-day failure');
is($bad->dbh->{rollback},1,'failed second day is rolled back');
like($@,qr/forced day failure/,'original import error is preserved');

done_testing;
