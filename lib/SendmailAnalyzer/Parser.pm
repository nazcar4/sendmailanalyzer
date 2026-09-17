package SendmailAnalyzer::Parser;
use strict;
use warnings;
use SendmailAnalyzer::Parser::Postfix;
use SendmailAnalyzer::Parser::SpamAssassin;
use SendmailAnalyzer::Parser::Rspamd;
use SendmailAnalyzer::Parser::OpenDKIM;
use SendmailAnalyzer::Parser::OpenDMARC;
use SendmailAnalyzer::Parser::ClamAV;
use SendmailAnalyzer::Parser::Postscreen;
use SendmailAnalyzer::Parser::Dovecot;
my @PARSERS = qw(
 SendmailAnalyzer::Parser::Postscreen SendmailAnalyzer::Parser::OpenDKIM
 SendmailAnalyzer::Parser::OpenDMARC SendmailAnalyzer::Parser::ClamAV
 SendmailAnalyzer::Parser::Rspamd SendmailAnalyzer::Parser::SpamAssassin
 SendmailAnalyzer::Parser::Dovecot SendmailAnalyzer::Parser::Postfix
);
sub _configured_header_route {
    my ($line,$routes,$ignore)=@_;
    return (undef,0) if ref($routes) ne 'HASH' && ref($ignore) ne 'HASH';
    my @headers=map { lc $_ } ($line =~ /\b(X-[A-Za-z][A-Za-z0-9-]*):/ig);
    if (ref($ignore) eq 'HASH') {
        for my $header (@headers) { return (undef,1) if $ignore->{$header}; }
    }
    my $engine;
    if (ref($routes) eq 'HASH') {
        # Later header names win.  This is intentional for Postfix
        # milter-header-replace lines: the rewritten destination header occurs
        # after the original standard header and can disambiguate engines that
        # both use X-Spam-Status.
        for my $header (@headers) { $engine=$routes->{$header} if exists $routes->{$header}; }
    }
    return ($engine,0);
}
sub parse_line {
    my ($class,$line,%opt)=@_;
    my ($route,$ignore)=_configured_header_route($line,$opt{header_routes},$opt{header_ignore});
    return if $ignore;
    $opt{header_route_engine}=$route if defined $route;
    for my $parser (@PARSERS) { my $e=$parser->parse($line,%opt); return $e if $e; }
    return;
}
sub parser_names { return @PARSERS; }
1;
