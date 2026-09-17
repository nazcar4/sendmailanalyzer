package SendmailAnalyzer::Event;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    $args{meta} ||= {};
    return bless \%args, $class;
}

sub as_hash {
    my ($self) = @_;
    return { %{$self} };
}

1;
