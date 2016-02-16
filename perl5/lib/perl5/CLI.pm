#!/usr/bin/perl -w

package CLI;

use strict;
use File::Basename;
use File::Spec;
use Getopt::Long;
use IPC::Run3;
use POSIX;
use Term::ReadKey;
use Term::ANSIColor;

our @ISA = qw(Exporter);
our @EXPORT = qw(println);

our $HOME = $ENV{"HOME"};
our $COMMAND = basename($0);



# options

sub options {
    my @definitions = @_;

    push(@definitions, "help|h|?");

    my %options;

    GetOptions(\%options, @definitions);

    return \%options;
}


# run

sub can_run {
    my $command = shift;

    assert_parameter($command);

    my $path = CLI::run("which $command");

    return $path ? 1 : 0;
}



sub run {
    my $command = shift;
    my $options = shift;

    assert_parameter($command);

    my $wantarray = wantarray() || 0;
    my $wantscalar = (defined(wantarray()) && !$wantarray) || 0;

    my $assertonerror = defined($options->{"assertonerror"}) ? $options->{"assertonerror"} : (!$wantarray && !$wantscalar);
    my $input = $options->{"input"};
    my $showcommand = defined($options->{"showcommand"}) ? $options->{"showcommand"} : 0;
    my $showoutput = defined($options->{"showoutput"}) ? $options->{"showoutput"} : 0;
    my $showerrors = defined($options->{"showerrors"}) ? $options->{"showerrors"} : 0;

    my $inputref;
    my $outputref;
    my $errorsref = [];

    if($input) {
        foreach my $line (@{$input}) {
            push(@{$inputref}, "$line\n");
        }
    }

    if($showoutput || ($wantarray || $wantscalar)) {
        $outputref = [];
    }

    if($showcommand) {
        println $command;
    }

    run3($command, $inputref, $outputref, $errorsref, { "return_if_system_error" => 1 });

    if($assertonerror) {
        assert_false($? == -1, "Command \"$command\" failed with error \"$!\"");
    } else {
        return if $? == -1;
    }

    if($showerrors) {
        foreach my $line (@{$errorsref}) {
            print $line;
        }
    }

    if($showoutput) {
        foreach my $line (@{$outputref}) {
            print $line;
        }
    }

    my $status = $? >> 8;

    if($assertonerror) {
        if($status != 0 && !$showerrors) {
            foreach my $line (@{$errorsref}) {
                print $line;
            }
        }

        assert_true($status == 0, "Command \"$command\" failed with status $status");
    } else {
        return unless $status == 0;
    }

    if($wantarray) {
        my @result;

        foreach my $line (@{$outputref}) {
            chomp($line);
            push(@result, $line);
        }

        return @result;
    }
    elsif($wantscalar) {
        my $line = shift(@{$outputref});

        if($line) {
            chomp($line);

            return $line;
        }
    }
}



# terminal

sub stringwidth {
    my $string = shift;

    assert_parameter($string);

    return length(Term::ANSIColor::colorstrip($string));
}

sub terminalwidth {
    return (GetTerminalSize())[0];
}

sub terminalwidthstring {
    my $string = shift;
    my $offset = shift || 0;

    assert_parameter($string);

    my $width = terminalwidth() - $offset;

    while(stringwidth($string) > $width) {
        chop($string);
    }

    while(stringwidth($string) < $width) {
        $string .= " ";
    }

    return $string;
}

sub coloredstring {
    my $string = shift;
    my $format = shift || "";

    assert_parameter($string);

    sub colornames {
        my @names;

        push(@names, normalcolornames());
        push(@names, brightcolornames());

        return @names;
    }

    sub normalcolornames {
        return ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white");
    }

    sub brightcolornames {
        my @names;

        foreach my $name (normalcolornames()) {
            push(@names, "bright $name");
        }

        return @names;
    }

    sub colorname {
        my $string = shift;

        if($string eq "" || $string eq "-" || $string eq "none") {
            return "none";
        }

        $string = lc(trimmedstring($string));

        if($string =~ /^b([a-z])$/) {
            $string = "bright $1";
        }


        foreach my $name (colornames()) {
            if($string eq substr($name, 0, length($string))) {
                return $name;
            }
        }

        return "none";
    }

    sub attributenames {
        return ("bold", "dimmed", "underlined", "blinking", "inverted", "hidden");
    }

    sub attributename {
        my $string = shift;

        if($string eq "" || $string eq "-" || $string eq "none") {
            return "none";
        }

        $string = lc(trimmedstring($string));

        foreach my $name (attributenames()) {
            if($string eq substr($name, 0, length($string))) {
                return $name;
            }
        }

        return "none";
    }

    my %foregroundcodes = ("none" => 39);
    my %attributecodes = ("none" => 0, "bold" => 1, "dimmed" => 2, "underlined" => 4, "blinking" => 5, "inverted" => 7, "hidden" => 8);
    my %backgroundcodes = ("none" => 49);

    my $code = 30;

    foreach my $name (normalcolornames()) {
        $foregroundcodes{$name} = $code++;
    }

    $code = 90;

    foreach my $name (brightcolornames()) {
        $foregroundcodes{$name} = $code++;
    }

    $code = 40;

    foreach my $name (normalcolornames()) {
        $backgroundcodes{$name} = $code++;
    }

    $code = 100;

    foreach my $name (brightcolornames()) {
        $backgroundcodes{$name} = $code++;
    }

    my @formats = split(",", $format);

    my $foregroundname = @formats > 0 ? colorname($formats[0]) : "none";
    my $attributename = @formats > 1 ? attributename($formats[1]) : "none";
    my $backgroundname = @formats > 2 ? colorname($formats[2]) : "none";

    my $startcode = sprintf("\033[%d;%d;%dm", $attributecodes{$attributename}, $foregroundcodes{$foregroundname}, $backgroundcodes{$backgroundname});
    my $stopcode = sprintf("\033[0m");

    return sprintf("%s%s%s", $startcode, $string, $stopcode);
}



# string

sub trimmedstring {
    my $string = shift;

    assert_parameter($string);

    $string =~ s/(^\s+|\s+$)//g;

    return $string;
}

sub justifiedstring {
    my $string = shift;
    my $minwidth = shift;
    my $maxwidth = shift || -1;

    assert_parameter($string);
    assert_parameter($minwidth);

    if($minwidth > 0) {
        return sprintf("%-*.*s", $minwidth, $maxwidth, $string);
    } else {
        return sprintf("%*.*s", -$minwidth, $maxwidth, $string);
    }
}



# time

sub formattedtime {
    my $format = shift || "%Y-%m-%d %H:%M:%S";;
    my $time = shift || time();

    return POSIX::strftime($format, localtime($time));
}



# path

sub absolutepath {
    my $path = shift;

    assert_parameter($path);

    return File::Spec->rel2abs($path);
}

sub lastpathcomponent {
    my $path = shift;

    assert_parameter($path);

    return basename($path);
}

sub pathbydeletinglastpathcomponent {
    my $path = shift;

    assert_parameter($path);

    return dirname($path);
}

sub pathbyjoiningpathcomponents {
    my @components = @_;

    return join("/", @components);
}



# verification

sub isfile {
    my $file = shift;

    return 0 unless $file;

    return 1;
}



# assert

sub assert_true {
    fatal($_[1]) unless $_[0];
}

sub assert_false {
    fatal($_[1]) if $_[0];
}

sub assert_defined {
    fatal($_[1]) unless defined($_[0]);
}

sub assert_undefined {
    fatal($_[1]) if defined($_[0]);
}

sub assert_parameter {
    fatal("Missing parameter at " . _assert_callsitestring()) unless defined($_[0]);
}

sub _assert_callsitestring {
    my @callsite = caller(1);

    return $callsite[1] . ":" . $callsite[2];
}



# output

sub println {
    return print @_, "\n";
}

sub fatal {
    my $message = shift;

    chomp($message);
    println "$COMMAND: $message";

    exit(1);
}

sub error {
    my $message = shift;

    chomp($message);
    println "$COMMAND: $message";
}

sub usage {
    my @messages = @_;

    my $prefix = "Usage: $COMMAND ";

    foreach my $message (@messages) {
        chomp($message);

        println $prefix, $message;

        $prefix = "";
    }

    exit(2);
}

1;
