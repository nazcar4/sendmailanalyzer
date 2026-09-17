package SendmailAnalyzer::LogReader;
use strict;
use warnings;
use IO::Uncompress::Gunzip qw($GunzipError);

sub open_reader {
    my ($class,$path)=@_;
    die "Log path required\n" if !defined($path) || $path eq '';
    if ($path =~ /\.gz\z/i) {
        my $fh=IO::Uncompress::Gunzip->new($path, MultiStream=>1)
            or die "Cannot open compressed log $path: $GunzipError\n";
        return ($fh,1);
    }
    open my $fh,'<',$path or die "Cannot open $path: $!\n";
    return ($fh,0);
}

1;
