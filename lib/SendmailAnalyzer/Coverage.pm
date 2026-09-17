package SendmailAnalyzer::Coverage;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use SendmailAnalyzer::Parser;

sub new { bless {total=>0,parsed=>0,ignored=>0,unknown=>0,by_source=>{},unknown_samples=>{},ignored_reason=>{}}, shift }
sub _known_noise {
    my ($line)=@_;
    return 'rspamd native log detail' if $line =~ /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+#\d+\([^)]+\)\s+/;
    return 'rsyslog/rotation' if $line =~ /(?:rsyslogd|logrotate)/;
    return 'postfix lifecycle' if $line =~ /postfix\/postfix-script\[\d+\]:\s+(?:refreshing|starting|stopping) the Postfix mail system/i;
    return 'spamd worker bookkeeping' if $line =~ /spamd\[\d+\]:\s+spamd:\s+server killed by SIGTERM, shutting down/i;
    return 'postfix bookkeeping' if $line =~ /postfix\/(?:anvil|scache|tlsmgr|master)\[/;
    return 'postfix queue lifecycle' if $line =~ /postfix\/(?:pickup|cleanup|qmgr)\[/ && $line =~ /(?:uid=|warning:|statistics:|refreshing|starting)/;
    return 'postscreen connection bookkeeping' if $line =~ /postfix\/(?:smtp\/)?postscreen\[/ && $line =~ /(?:cache lmdb:.*full cleanup:)/i;
    return 'postfix connection detail' if $line =~ /postfix\/(?:[^\/]+\/)?smtpd\[/ && $line =~ /(?:lost connection|timeout after|improper command pipelining|non-SMTP command|too many errors)/;
    return 'postfix informational headers' if $line =~ /postfix\/cleanup\[/ && $line =~ /milter-header-(?:replace|add):\s+header (?:X-Rspamd-(?:Queue-Id|Server)|X-Virus-Scanned)/i;
    return 'opendkim connection metadata' if $line =~ /opendkim\[/ && $line =~ /:\s+(?:not authenticated|[^:]+\s+\[[^\]]+\]\s+not internal|message has signatures from\s+)/;
    return 'opendmarc connection metadata' if $line =~ /opendmarc\[/ && $line =~ /(?:ignoring connection from|implicit authentication service:|ignoring Authentication-Results at)/;
    return 'spamd worker bookkeeping' if $line =~ /spamd\[/ && $line =~ /(?:connection from|setuid to|checking message|prefork:|child \[?\d+\]? killed successfully|server started on|server pid:|server socket closed|server hit by SIGHUP|server successfully spawned child process|zoom: able to use|handle_user \(userdir\) unable to find user|pyzor:|Did not receive a response from the pyzor server|async: aborting after)/;
    return 'dovecot bookkeeping' if $line =~ /dovecot:/ && $line =~ /(?:Disconnected: Logged out|Disconnected: Inactivity|Connection closed|Aborted login|lmtp\([^)]*\):\s+(?:Connect from local|Disconnect from local))/;
    return;
}
sub add_line {
    my ($self,$line,%opt)=@_; $self->{total}++;
    my $e=SendmailAnalyzer::Parser->parse_line($line,%opt);
    if ($e) { $self->{parsed}++; my $h=(blessed($e) && $e->can('as_hash')) ? $e->as_hash : $e; $self->{by_source}{$h->{source}||'unknown'}++; return 'parsed'; }
    if (ref($opt{header_ignore}) eq 'HASH') {
        my @headers=map { lc $_ } ($line =~ /\b(X-[A-Za-z][A-Za-z0-9-]*):/ig);
        if (grep { $opt{header_ignore}{$_} } @headers) { $self->{ignored}++; $self->{ignored_reason}{'configured header ignore'}++; return 'ignored'; }
    }
    if (my $r=_known_noise($line)) { $self->{ignored}++; $self->{ignored_reason}{$r}++; return 'ignored'; }
    $self->{unknown}++; my $sample=$line; $sample =~ s/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})/<TIME>/g; $sample =~ s/^[A-Z][a-z]{2}\s+\d+\s+\d\d:\d\d:\d\d/<TIME>/; $sample =~ s/\b[0-9A-F]{10,}\b/<QID>/g; $sample =~ s/\[\d+\]/[PID]/g; $sample =~ s/\b\d{1,3}(?:\.\d{1,3}){3}\b/<IP>/g; $sample =~ s/\bmpid=\d+/mpid=<PID>/g; $sample =~ s/session=<[^>]*>/session=<SESSION>/g; $sample =~ s/lmtp\(\d+\)/lmtp(<PID>)/g; $sample =~ s/\s+/ /g; chomp $sample; $sample=substr($sample,0,240); $self->{unknown_samples}{$sample}++; return 'unknown';
}
sub report { my ($self)=@_; my %x=%$self; $x{coverage_pct}=$self->{total}?sprintf('%.2f',100*($self->{parsed}+$self->{ignored})/$self->{total}):'100.00'; return \%x; }
1;
