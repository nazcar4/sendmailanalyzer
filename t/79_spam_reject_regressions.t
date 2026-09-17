use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

{
    package Local::FakeDBH;
    sub new { bless { calls => [] }, shift }
    sub calls { $_[0]->{calls} }
    sub selectall_arrayref {
        my ($self,$sql,$attr,@bind)=@_;
        push @{$self->{calls}}, [$sql, [@bind]];
        return [ { type=>'smtp_reject', reason=>'policy reject', count=>3 } ]
            if $sql =~ /FROM events WHERE type IN/;
        return [ { reason=>'legacy reject', count=>2 } ]
            if $sql =~ /FROM legacy_aggregates WHERE metric='smtp_rejected'/;
        return [];
    }
}

my $dbh=Local::FakeDBH->new;
my $st=bless { dbh=>$dbh }, 'SendmailAnalyzer::Storage::SQLite';

my $daily=$st->_legacy_agg_by_day('spam_detected','2026-08-17',undef);
is_deeply($daily, [], '_legacy_agg_by_day returns fake result');
my ($sql,$bind)=@{$dbh->calls->[0]};
is($sql,
   'SELECT day,COALESCE(SUM(count),0) count FROM legacy_aggregates WHERE metric=? AND day>=? GROUP BY day ORDER BY day',
   'legacy daily query keeps metric as a placeholder rather than a SQL identifier');
is_deeply($bind,['spam_detected','2026-08-17'],
   'legacy daily query binds metric and date separately');
unlike($sql,qr/\bspam_detected\b/,
   'spam_detected is never interpolated as a bare column name');

my $rej=$st->top_reject_reasons(30);
is(ref($rej),'ARRAY','reject ranking returns an array reference');
is_deeply(
    $rej,
    [
      { type=>'smtp_reject', reason=>'policy reject', count=>3 },
      { type=>'smtp_reject', reason=>'legacy reject', count=>2 },
    ],
    'reject ranking sorts hash rows without lexical $a shadowing sort $a'
);

done_testing;
