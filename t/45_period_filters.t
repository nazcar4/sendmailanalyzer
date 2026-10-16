use strict; use warnings; use Test::More; use FindBin qw($Bin);
my $web="$Bin/../web/sendmailanalyzer.psgi"; open my $fh,'<',$web or die $!; local $/; my $w=<$fh>;
like($w,qr/stats_range\(\$from,\$to\)/,'dashboard statistics obey selected day/hour range');
like($w,qr/recent_messages\(from=>\$from,to=>\$to/,'recent activity obeys selected period');
like($w,qr/top_senders\(8,\$from,\$to\)/,'top senders obey selected period');
like($w,qr/top_recipients\(8,\$from,\$to\)/,'top recipients obey selected period');
my $st="$Bin/../lib/SendmailAnalyzer/Storage/SQLite.pm"; open my $sf,'<',$st or die $!; local $/; my $s=<$sf>;
like($s,qr/sub stats_range/,'storage exposes bounded statistics');
like($s,qr/sub flow_summary/,'storage exposes period flow summary');
like($s,qr/COALESCE\(SUM\(size\),0\) size_bytes/,'hourly view includes traffic volume');

like(
    $w,
    qr/my \$console='';.*if\(\$period\)/s,
    'time console is rendered only for period-aware pages'
);

like(
    $w,
    qr/if\(\$path eq '\/messages'\).*selected_period.*recent_messages\(.*from=>\$period->\{from\}.*to=>\$period->\{to\}/s,
    'messages page obeys selected period'
);

like(
    $w,
    qr/if\(\$path =~ m\{\^\/direction\/.*selected_period.*stats_range\(/s,
    'direction pages obey selected period'
);

like(
    $w,
    qr/top_ips\(\s*100,\s*\$period->\{from\},\s*\$period->\{to\}/s,
    'IP page obeys selected period'
);

like(
    $w,
    qr/top_senders\(\s*40,\s*\$period->\{from\},\s*\$period->\{to\}/s,
    'sender page obeys selected period'
);

like(
    $w,
    qr/top_recipients\(\s*40,\s*\$period->\{from\},\s*\$period->\{to\}/s,
    'recipient page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/status'\).*selected_period.*stats_range\(/s,
    'status page obeys selected period'
);

like(
    $w,
    qr/route_period\(\$period,'\/messages'\)/,
    'messages time navigation preserves messages route'
);

like(
    $w,
    qr/route_period\(\$period,'\/ips'\)/,
    'IP time navigation preserves IP route'
);

like(
    $w,
    qr/route_period\(\$period,'\/senders'\)/,
    'sender time navigation preserves sender route'
);

like(
    $w,
    qr/route_period\(\$period,'\/recipients'\)/,
    'recipient time navigation preserves recipient route'
);

like(
    $w,
    qr/route_period\(\$period,'\/status'\)/,
    'status time navigation preserves status route'
);


like(
    $s,
    qr/sub top_reject_reasons.*my \(\$self,\$limit,\$from,\$to\)/s,
    'reject reason statistics support selected periods'
);

like(
    $s,
    qr/sub engine_stats.*my \(\$self,\$from,\$to\)/s,
    'engine statistics support selected periods'
);

like(
    $s,
    qr/sub rspamd_native_stats.*my \(\$self,\$from,\$to\)/s,
    'native Rspamd statistics support selected periods'
);

like(
    $s,
    qr/sub dsn_stats.*my \(\$self,\$from,\$to\)/s,
    'DSN statistics support selected periods'
);

like(
    $s,
    qr/sub top_viruses.*my \(\$self,\$limit,\$from,\$to\)/s,
    'virus rankings support selected periods'
);


like(
    $w,
    qr/if\(\$path eq '\/spam'\).*selected_period.*stats_range\(.*recent_messages\(.*spam=>1/s,
    'spam page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/viruses'\).*selected_period.*top_viruses\(.*\$period->\{from\}.*\$period->\{to\}/s,
    'virus page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/rejects'\).*selected_period.*top_reject_reasons\(.*\$period->\{from\}.*\$period->\{to\}/s,
    'rejections page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/rspamd'\).*selected_period.*rspamd_native_stats\(.*\$period->\{from\}.*\$period->\{to\}/s,
    'Rspamd page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/dsn'\).*selected_period.*dsn_stats\(.*\$period->\{from\}.*\$period->\{to\}/s,
    'DSN page obeys selected period'
);

like(
    $w,
    qr/if\(\$path eq '\/security'\).*selected_period.*stats_range\(/s,
    'security overview obeys selected period'
);

like(
    $w,
    qr/period_path\('\/spam',\$period\)/,
    'security overview preserves period when opening child reports'
);

like(
    $w,
    qr/route_period\(\$period,'\/security'\)/,
    'security time navigation preserves security route'
);

like(
    $s,
    qr/sub _selected_legacy_hour/,
    'storage detects exact legacy hourly selections'
);

like(
    $s,
    qr/sub _legacy_agg_sum.*_selected_legacy_hour/s,
    'legacy aggregate totals respect exact selected hour'
);

done_testing;
