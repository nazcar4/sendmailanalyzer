package SendmailAnalyzer::Parser::SpamAssassin;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($c,%x)=@_; SendmailAnalyzer::Event->new(%$c,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);

    # SpamAssassin's standard X-Spam-Status header provides Queue-ID based
    # correlation when Postfix logs the milter header operation.  Do not rely
    # on locally renamed/custom headers: the original standard header is the
    # portable evidence across installations.
    if ($line =~ /^postfix\/cleanup\[\d+\]:\s+([A-Za-z0-9]+):\s+milter-header-(?:add|replace):\s+header X-Spam-Status:\s*(Yes|No),\s*score=(-?\d+(?:\.\d+)?)(.*?)\s+from\s+/i) {
        my ($qid,$yn,$score,$middle)=($1,$2,$3,$4);
        my $route=$opt{header_route_engine};
        my $looks_sa=($middle =~ /\b(?:required|tests)=/i) ? 1 : 0;
        if ((!defined($route) && $looks_sa) || (defined($route) && $route eq 'spamassassin')) {
            my ($req)=$middle =~ /\brequired=(-?\d+(?:\.\d+)?)/;
            my ($tests_txt)=$middle =~ /\btests=(.*?)(?:\s+autolearn=|\s+from\s+|$)/;
            my @tests=defined($tests_txt) ? grep { length } split /,/, $tests_txt : ();
            return _ev($common,source=>'spamassassin',type=>'verdict',queue_id=>$qid,detected=>(lc($yn) eq 'yes'?1:0),score=>0+$score,required_score=>defined($req)?0+$req:undef,tests=>\@tests,evidence=>'X-Spam-Status');
        }
    }

    return if $line !~ /^spamd\[\d+\]:\s+spamd:\s+(.*)$/;
    my $msg=$1;
    if ($msg =~ /^processing message <([^>]*)> aka <([^>]*)> for ([^:]+):(\d+)/) {
        return _ev($common,source=>'spamassassin',type=>'scan_start',message_id=>$2,original_message_id=>$1,user=>$3,uid=>0+$4,evidence=>'spamd aka');
    }
    if ($msg =~ /^processing message <([^>]*)> for ([^:]+):(\d+)/) {
        return _ev($common,source=>'spamassassin',type=>'scan_start',message_id=>$1,user=>$2,uid=>0+$3);
    }
    if ($msg =~ /^clean message \((-?\d+(?:\.\d+)?)\/(-?\d+(?:\.\d+)?)\)/) {
        return _ev($common,source=>'spamassassin',type=>'scan_summary',detected=>0,score=>0+$1,required_score=>0+$2);
    }
    if ($msg =~ /^identified spam \((-?\d+(?:\.\d+)?)\/(-?\d+(?:\.\d+)?)\)/) {
        return _ev($common,source=>'spamassassin',type=>'scan_summary',detected=>1,score=>0+$1,required_score=>0+$2);
    }
    if ($msg =~ /^result:\s+([Y.])\s+(-?\d+(?:\.\d+)?)\s+-\s+(.*?)\s+scantime=.*?required_score=(-?\d+(?:\.\d+)?).*?mid=<([^>]*)>,autolearn=([^\s,]+)/) {
        my ($mark,$score,$tests,$req,$mid,$al)=($1,$2,$3,$4,$5,$6);
        my @tests=grep { length } split /,/, $tests;
        return _ev($common,source=>'spamassassin',type=>'verdict',message_id=>$mid,detected=>($mark eq 'Y'?1:0),score=>0+$score,required_score=>0+$req,tests=>\@tests,autolearn=>$al,evidence=>'spamd');
    }
    return;
}
1;
