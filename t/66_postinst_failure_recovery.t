use strict; use warnings; use Test::More; use FindBin qw($Bin);
sub slurp { my($f)=@_; open my $h,'<',$f or die $!; local $/; <$h> }
my $pre=slurp("$Bin/../debian/preinst");
like($pre,qr/runtime-services\.active/,'preinst records active SendmailAnalyzer services');
like($pre,qr/systemctl is-active --quiet/, 'service state is captured before stop');
my $post=slurp("$Bin/../debian/postinst");
like($post,qr/restore_runtime_on_failure/,'postinst has failure recovery routine');
like($post,qr/while IFS= read -r svc.*systemctl start/s,'failure recovery restarts previously active SendmailAnalyzer services');
like($post,qr/main \"\$@\"\s*\nrc=\$\?\s*\nif \[ \"\$rc\" -ne 0 \]/s,'postinst recovery runs for any failed configure path');
done_testing;
