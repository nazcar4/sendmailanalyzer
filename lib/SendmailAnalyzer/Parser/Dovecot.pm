package SendmailAnalyzer::Parser::Dovecot;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($common,%x)=@_; SendmailAnalyzer::Event->new(%$common,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);
    return if $line !~ /^dovecot:\s+(.*)$/;
    my $msg=$1;
    if ($msg =~ /^(imap-login|pop3-login):\s+(?:Login|Logged in):\s+user=<([^>]*)>,\s+method=([^,]+),\s+rip=([^,]+),\s+lip=([^,]+)(.*)$/) {
        return _ev($common,source=>'dovecot',type=>'login',protocol=>$1,user=>$2,method=>$3,remote_ip=>$4,local_ip=>$5,detail=>$6,success=>1);
    }
    if ($msg =~ /^(imap-login|pop3-login):\s+Login aborted:\s*(.*?):\s+user=<([^>]*)>,\s+method=([^,]+),\s+rip=([^,]+),\s+lip=([^,]+)(.*)$/) {
        return _ev($common,source=>'dovecot',type=>'login',protocol=>$1,user=>$3,method=>$4,remote_ip=>$5,local_ip=>$6,detail=>$2.$7,success=>0);
    }
    if ($msg =~ /^(imap-login|pop3-login):\s+Login aborted:\s*(.*?):\s+user=<([^>]*)>,\s+rip=([^,]+),\s+lip=([^,]+)(.*)$/) {
        return _ev($common,source=>'dovecot',type=>'login',protocol=>$1,user=>$3,remote_ip=>$4,local_ip=>$5,detail=>$2.$6,success=>0);
    }
    if ($msg =~ /^(imap-login|pop3-login):\s+Disconnected.*?user=<([^>]*)>.*?rip=([^,\s]+)/) {
        return _ev($common,source=>'dovecot',type=>'disconnect',protocol=>$1,user=>$2,remote_ip=>$3);
    }
    if ($msg =~ /^auth:.*?(?:passwd-file|sql|pam)?\([^,]*,([^,\)]+),([^\)]+)\):\s+Password mismatch/i) {
        return _ev($common,source=>'dovecot',type=>'login',user=>$1,remote_ip=>$2,success=>0,detail=>'Password mismatch');
    }
    if ($msg =~ /^lmtp\(([^\)]*)\).*?msgid=<([^>]*)>.*?(?:saved mail to|sieve: msgid=<[^>]*>: stored mail into mailbox)\s+'?([^']*)'?/i) {
        return _ev($common,source=>'dovecot',type=>'lmtp_saved',user=>$1,message_id=>$2,mailbox=>$3);
    }
    if ($msg =~ /^lmtp\(([^\)]*)\).*?msgid=<([^>]*)>/i) {
        return _ev($common,source=>'dovecot',type=>'lmtp',user=>$1,message_id=>$2);
    }
    return;
}
1;
