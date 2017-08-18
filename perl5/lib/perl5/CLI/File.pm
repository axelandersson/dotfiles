#!/usr/bin/perl -w

package CLI::File;

use strict;
use File::Copy ();
use File::Slurp;
use Mac::PropertyList;



# checks

sub isfileordirectory {
    my $argument = shift;

    return ($argument && -e $argument);
}

sub isfile {
    my $argument = shift;

    return ($argument && -e $argument && ! -d $argument);
}

sub isdirectory {
    my $argument = shift;

    return ($argument && -d $argument);
}



# file operations

sub readlines {
    my $path = shift;

    CLI::assertparameter($path);

    my @lines;

    if($path eq "-") {
        foreach my $line (<>) {
            chomp($line);
            push(@lines, $line);
        }
    } else {
        my $result = open(FH, $path);

        CLI::asserttrue($result, $!);

        foreach my $line (<FH>) {
            chomp($line);
            push(@lines, $line);
        }

        close(FH);
    }

    return @lines;
}

sub writelines {
    my $path = shift;
    my $lines = shift;

    CLI::assertparameter($path);
    CLI::assertparameter($lines);

    if($path eq "-") {
        foreach my $line (@{$lines}) {
            print $line, "\n";
        }
    } else {
        my $result = open(FH, ">" . $path);

        CLI::asserttrue($result, "$path: $!");

        foreach my $line (@{$lines}) {
            print FH $line, "\n";
        }

        close(FH);
    }
}

sub readdirectory {
    my $path = shift;

    CLI::assertparameter($path);

    my $result = opendir(DH, CLI::normalizepath($path));

    CLI::asserttrue($result, $!);

    my @files = grep { !/^\./ } readdir(DH);

    closedir(DH);

    return @files;
}

sub readplist {
    my $path = shift;

    CLI::assertparameter($path);

    my $data = File::Slurp::read_file(CLI::normalizepath($path));

    CLI::assertdefined($data, "$path: $!");

    my $plist = Mac::PropertyList::parse_plist($data);

    CLI::assertdefined($plist, "$path: $!");

    return $plist->as_perl;
}



# file system operations
sub move {
    my $sourcepath = shift;
    my $destinationpath = shift;

    CLI::assertparameter($sourcepath);
    CLI::assertparameter($destinationpath);

    my $result = File::Copy::move($sourcepath, $destinationpath);

    CLI::asserttrue($result, $!);

    return $result;
}

1;
