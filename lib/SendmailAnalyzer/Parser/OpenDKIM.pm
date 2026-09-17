package SendmailAnalyzer::Parser::OpenDKIM;
use strict;
use warnings;
use parent 'SendmailAnalyzer::Parser::Base';
use SendmailAnalyzer::Event;
sub _ev { my ($c,%x)=@_; SendmailAnalyzer::Event->new(%$c,%x) }
sub parse {
    my ($class,$raw,%opt)=@_;
    my ($line,$common)=$class->event_common($raw,%opt);
    return if $line !~ /^opendkim\[\d+\]:\s+(.*)$/;
    my $msg=$1;
    if ($msg =~ /^([A-Za-z0-9]+):\s+DKIM verification successful/) { return _ev($common,source=>'opendkim',type=>'dkim_verification',queue_id=>$1,result=>'pass'); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+DKIM verification failed(?:.*?:\s*(.*))?/) { return _ev($common,source=>'opendkim',type=>'dkim_verification',queue_id=>$1,result=>'fail',detail=>$2); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+no signature data/) { return _ev($common,source=>'opendkim',type=>'dkim_verification',queue_id=>$1,result=>'none'); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+bad signature data(?:\s*(.*))?$/i) { return _ev($common,source=>'opendkim',type=>'dkim_verification',queue_id=>$1,result=>'fail',detail=>$2||'bad signature data'); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+failed to parse authentication-results:\s*(.*)$/i) { return _ev($common,source=>'opendkim',type=>'dkim_metadata_error',queue_id=>$1,detail=>$2||'failed to parse authentication-results'); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+key retrieval failed \(s=([^,]+),\s*d=([^\)]+)\):\s*(.*)$/i) { return _ev($common,source=>'opendkim',type=>'dkim_key_error',queue_id=>$1,selector=>$2,domain=>$3,detail=>$4); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+s=([^\s]+)\s+d=([^\s]+)\s+a=([^\s]+)/) { return _ev($common,source=>'opendkim',type=>'dkim_signature',queue_id=>$1,selector=>$2,domain=>$3,algorithm=>$4); }
    if ($msg =~ /^([A-Za-z0-9]+):\s+DKIM-Signature field added \(s=([^,]+),\s*d=([^\)]+)\)/) { return _ev($common,source=>'opendkim',type=>'dkim_signing',queue_id=>$1,selector=>$2,domain=>$3,result=>'signed'); }
    return;
}
1;
