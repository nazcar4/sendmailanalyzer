package SendmailAnalyzer::MigrationPreflight;
use strict;
use warnings;
use SendmailAnalyzer::LegacySource;

sub scan {
    my ($class,%opt)=@_;
    my $root=$opt{root} || die 'root required';
    my $source=SendmailAnalyzer::LegacySource->new(root=>$root);
    my $files=$source->entries(type=>'senders');
    my %loc; my %hosts; my ($rows,$malformed,$synthetic)=(0,0,0); my ($min_date,$max_date);
    for my $entry (@$files) {
        my ($host,$date)=@{$entry}{qw(host date)}; $hosts{$host}=1;
        $min_date=$date if !defined($min_date) || $date lt $min_date;
        $max_date=$date if !defined($max_date) || $date gt $max_date;
        my $fh=$source->open_entry($entry);
        while (my $line=<$fh>) {
            next if $line !~ /\S/; $rows++;
            chomp $line; my (undef,$qid)=split /:/,$line,3;
            if (!defined($qid) || $qid !~ /^[A-Za-z0-9]+$/) { $malformed++; next; }
            if ($qid =~ /^(?:FaKe|NOQUEUE$)/) { $synthetic++; next; }
            $loc{$qid}{"$host/$date"}=1;
        }
        $source->close_entry($fh,$entry);
    }
    my @dupes;
    for my $qid (sort keys %loc) {
        my @where=sort keys %{$loc{$qid}};
        push @dupes,{queue_id=>$qid,locations=>\@where} if @where>1;
    }
    return {
        root=>$root,
        sender_files=>0+@$files,
        sample_sender_file=>(@$files ? ($files->[0]{kind} eq 'file' ? $files->[0]{path} : $files->[0]{archive}.':'.$files->[0]{member}) : undef),
        sender_rows=>$rows,
        synthetic_sender_rows=>$synthetic,
        real_sender_rows=>$rows-$synthetic,
        unique_queue_ids=>0+scalar(keys %loc),
        malformed_sender_rows=>$malformed,
        duplicate_queue_ids=>0+@dupes,
        duplicate_examples=>\@dupes,
        hosts=>[sort keys %hosts],
        min_date=>$min_date,
        max_date=>$max_date,
        history_archives=>$source->archives,
        archived_sender_files=>0+scalar(grep { $_->{kind} eq 'archive' } @$files),
    };
}
1;
