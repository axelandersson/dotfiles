#!/usr/bin/perl -w

package CLI::File;

use strict;
use File::Copy;



# operations

sub move_path {
    my $sourcepath = shift;
    my $destinationpath = shift;

    CLI::assert_parameter($sourcepath);
    CLI::assert_parameter($destinationpath);

    CLI::assert_true(move($sourcepath, $destinationpath), $!);

    return 1;
}

1;
