use strict; use warnings; use Test::More; use FindBin qw($Bin); use lib "$Bin/../lib";
use File::Temp qw(tempdir); use File::Path qw(make_path); use SendmailAnalyzer::LegacyImporter;
{
 package MockStorage;
 sub new { bless {events=>[],messages=>[],rcpt=>[]},shift }
 sub store_event { my($s,$e)=@_; push @{$s->{events}},$e->as_hash; 1 }
 sub upsert_message { my($s,$m)=@_; push @{$s->{messages}},$m; 1 }
 sub store_delivery_recipient { my($s,$e)=@_; push @{$s->{rcpt}}, {%$e}; 1 }
}
my $root=tempdir(CLEANUP=>1); my $d="$root/mailhost/2026/09/15"; make_path($d);
my %files=(
 'senders.dat'=>"120000:QID001:user\@example.test:1234:1:localhost:\n",
 'recipient.dat'=>"120001:QID001:dest\@example.net:mx.example.net:Sent\n",
 'spam.dat'=>"120002:QID002:bad\@example.net:user\@example.test:spamd\n",
 'virus.dat'=>"120003:QID003:Inline:Eicar-Test-Signature\n",
 'dsn.dat'=>"120004:QID004:SRC001:Bounced\n",
 'auth.dat'=>"120005:anonymous:mx.example.net:TLS_AES_256_GCM_SHA384 (256/256 bits):TLSv1.3\n120006:testuser:client.example.net:PLAIN:SASL\n",
 'rejected.dat'=>"120007:QID005:check_relay:bad.example:sender\@bad.example:blocked using dnsbl.example\n",
 'spf_dkim.dat'=>"120008:QID006:dkim:verification:example.org:pass\n",
 'starttls.dat'=>"120009:FAIL=1;NO=2;OK=3\n",
 'syserr.dat'=>"120010:QID007:temporary failure: extra detail\n",
 'other.dat'=>"120011:warning: some detail\n",
 'spamd.dat'=>"120012:QID008:spamd:6.2:cache:disabled:spam\n",
 'postgrey.dat'=>"120013:QID009:mx.example.net:sender\@example.net:dest\@example.test:greylist:deferred\n",
);
for my $f(keys %files){ open my $fh,'>',"$d/$f" or die $!; print {$fh} $files{$f}; close $fh; }
my $st=MockStorage->new; my $i=SendmailAnalyzer::LegacyImporter->new(storage=>$st); my $r=$i->import_tree($root);
is($r->{files},13,'all legacy .dat files discovered'); is($r->{lines},14,'all lines read');
my %types; $types{$_->{type}}++ for @{$st->{events}};
for my $t(qw(envelope delivery spam virus_verdict dsn tls smtp_auth smtp_reject authentication_result starttls_aggregate system_error other spam_detail greylist)){ ok($types{$t},"imported $t"); }
is(scalar @{$st->{rcpt}},1,'delivery recipient normalized');
my ($tls)=grep {$_->{type} eq 'tls'} @{$st->{events}}; is($tls->{protocol},'TLSv1.3','legacy TLS protocol retained');
my ($auth)=grep {$_->{type} eq 'smtp_auth'} @{$st->{events}}; is($auth->{username},'testuser','legacy SMTP auth user retained');
my ($virus)=grep {$_->{type} eq 'virus_verdict'} @{$st->{events}}; is($virus->{virus},'Eicar-Test-Signature','legacy virus name retained');
my ($dsn)=grep {$_->{type} eq 'dsn'} @{$st->{events}}; is($dsn->{status},'Bounced','legacy DSN status retained');
my ($detail)=grep {$_->{type} eq 'spam_detail'} @{$st->{events}}; is($detail->{engine},'spamd','dynamic spam-detail engine retained'); is($detail->{score},'6.2','dynamic spam-detail score retained');
my ($grey)=grep {$_->{type} eq 'greylist'} @{$st->{events}}; is($grey->{status},'deferred','legacy postgrey status retained');
done_testing;
