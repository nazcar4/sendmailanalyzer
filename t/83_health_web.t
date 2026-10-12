use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);

use lib "$Bin/../lib";
use SendmailAnalyzer::Storage::SQLite;

my $dir=tempdir(CLEANUP=>1);
my $db="$dir/web-health.sqlite3";
my $cfg="$dir/sendmailanalyzer.conf";

my $st=SendmailAnalyzer::Storage::SQLite->new(file=>$db);
$st->set_state('/var/log/mail.log',123,456,'2026-10-12T23:45:00+0200');
undef $st;

open my $cf,'>:encoding(UTF-8)',$cfg or die $!;
print {$cf} "DB_FILE $db\n";
print {$cf} "WEB_PAGE_SIZE 100\n";
close $cf;

local $ENV{SENDMAILANALYZER_CONFIG}=$cfg;

my $app=do "$Bin/../web/sendmailanalyzer.psgi";
die $@ if $@;
die $! if !defined $app;
ok(ref($app) eq 'CODE','PSGI application loads');

my $api=$app->({
    PATH_INFO=>'/api/health',
    QUERY_STRING=>'',
    REQUEST_METHOD=>'GET',
});
is($api->[0],200,'health API returns HTTP 200');

my $json=decode_json(join('',@{$api->[2]}));
is($json->{quick_check},'not_run','health API is lightweight by default');
ok(exists $json->{counts}{messages},'health API exposes database counters');
ok(ref($json->{collectors}) eq 'ARRAY','health API exposes collector state');

my $checked=$app->({
    PATH_INFO=>'/api/health',
    QUERY_STRING=>'check=1',
    REQUEST_METHOD=>'GET',
});
is($checked->[0],200,'checked health API returns HTTP 200');

my $checked_json=decode_json(join('',@{$checked->[2]}));
is($checked_json->{quick_check},'ok','explicit API database check runs quick_check');

my $page=$app->({
    PATH_INFO=>'/health',
    QUERY_STRING=>'',
    REQUEST_METHOD=>'GET',
});
is($page->[0],200,'health page returns HTTP 200');

my $html=join('',@{$page->[2]});
like($html,qr/>Health</,'health page has Health heading/navigation');
like($html,qr/Overall status/,'health page renders overall status');
like($html,qr/Collector state/,'health page renders collector state');
like($html,qr/Source activity/,'health page renders source activity');
like($html,qr/Data quality/,'health page renders data quality');
like($html,qr{/health\?check=1},'health page offers explicit SQLite check');
unlike($html,qr/<script\b/i,'health page introduces no JavaScript');
unlike($html,qr/style\s*=\s*["']/i,'health page introduces no inline styles');

done_testing;
