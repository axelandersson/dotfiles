#!/usr/bin/perl -w

package CLI;

use strict;
use File::Basename;
use File::Spec;
use Getopt::Long qw(:config pass_through);
use IPC::Run3;
use POSIX;
use Term::ReadKey;
use Term::ANSIColor;

our @ISA = qw(Exporter);
our @EXPORT = qw(println);
our $DEBUG = 0;



# options

sub options {
    my @specifiers = @_;

    push(@specifiers, "help|h|?");

    my %options;
    my $result = GetOptions(\%options, @specifiers);

    asserttrue($result, $!);

    return \%options;
}



# run

sub canrun {
    my $command = shift;

    assertparameter($command);

    my $path = run("which $command");

    return $path ? 1 : 0;
}



sub run {
    my $command = shift;
    my $options = shift;

    assertparameter($command);

    my $wantarray = wantarray() || 0;
    my $wantscalar = (defined(wantarray()) && !$wantarray) || 0;

    my $assertonerror = defined($options->{"assertonerror"}) ? $options->{"assertonerror"} : (!$wantarray && !$wantscalar);
    my $input = $options->{"input"};
    my $rawinput = $options->{"rawinput"};
    my $showcommand = defined($options->{"showcommand"}) ? $options->{"showcommand"} : $DEBUG;
    my $showoutput = defined($options->{"showoutput"}) ? $options->{"showoutput"} : 0;
    my $showerrors = defined($options->{"showerrors"}) ? $options->{"showerrors"} : 0;

    my $commandstring = (ref($command) eq "ARRAY") ? join(" ", @{$command}) : $command;
    my $inputref;
    my $outputref;
    my $errorsref = [];

    if($input) {
        foreach my $line (@{$input}) {
            $line ||= "";

            push(@{$inputref}, "$line\n");
        }
    }
    elsif($rawinput) {
        push(@{$inputref}, $rawinput);
    }

    if($showoutput || ($wantarray || $wantscalar)) {
        $outputref = [];
    }

    if($showcommand) {
        println($commandstring);
    }

    run3($command, $inputref, $outputref, $errorsref, { "return_if_system_error" => 1 });

    if($assertonerror) {
        assertfalse($? == -1, "Command \"$commandstring\" failed with error \"$!\"");
    } else {
        return undef if $? == -1;
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

        asserttrue($status == 0, "Command \"$commandstring\" failed with status $status");
    } else {
        return undef unless $status == 0;
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

sub runpager {
    my $input = shift;
    my $options = shift;

    my $pager = $options->{"pager"} || $ENV{"PAGER"};

    run([$pager], { "input" => $input });
}



# terminal

sub ask {
    my $prefix = shift;

    print $prefix, ": ";

    my $string = <>;

    chomp($string);

    return $string;
}

sub askwithoutecho {
    my $prefix = shift;

    ReadMode('noecho');

    my $string = ask($prefix);

    ReadMode(0);

    print "\n";

    return $string;
}

sub stringwidth {
    my $string = shift;

    assertparameter($string);

    return length(Term::ANSIColor::colorstrip($string));
}

sub terminalwidth {
    return (GetTerminalSize())[0];
}

sub terminalwidthstring {
    my $string = shift;
    my $offset = shift || 0;

    assertparameter($string);

    my $width = terminalwidth() - $offset;

    while(stringwidth($string) > $width) {
        chop($string);
    }

    while(stringwidth($string) < $width) {
        $string .= " ";
    }

    return $string;
}

sub coloredstringcodes {
    my $format = shift;

    assertparameter($format);

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

    return ($startcode, $stopcode);
}

sub coloredstring {
    my $string = shift;
    my $format = shift || "";

    assertparameter($string);

    my($startcode, $stopcode) = coloredstringcodes($format);

    return sprintf("%s%s%s", $startcode, $string, $stopcode);
}



# array

sub trimmedarray {
    my @array = @_;

    my $firstemptyindex;
    my $lastemptyindex;

    for(my $i = 0; $i < @array; $i++) {
        my $isempty = ($array[$i] eq "" || trimmedstring($array[$i]) eq "") ? 1 : 0;

        if(!defined($firstemptyindex) && !$isempty) {
            $firstemptyindex = $i;
        }

        if(!$isempty) {
            $lastemptyindex = $i;
        }
    }

    if(defined($firstemptyindex) && defined($lastemptyindex)) {
        return splice(@array, $firstemptyindex, $lastemptyindex - $firstemptyindex + 1);
    } else {
        return ();
    }
}



# string

sub trimmedstring {
    my $string = shift;

    assertparameter($string);

    $string =~ s/(^\s+|\s+$)//g;

    return $string;
}

sub justifiedstring {
    my $string = shift;
    my $minwidth = shift;
    my $maxwidth = shift || -1;

    assertparameter($string);
    assertparameter($minwidth);

    if($minwidth > 0) {
        return sprintf("%-*.*s", $minwidth, $maxwidth, $string);
    } else {
        return sprintf("%*.*s", -$minwidth, $maxwidth, $string);
    }
}



# time

sub formattedtime {
    my $time = shift || time();
    my $format = shift || "%Y-%m-%d %H:%M:%S";

    return POSIX::strftime($format, localtime($time));
}



# path

sub homepath {
    return $ENV{"HOME"};
}

sub commandpath {
    return absolutepath($0);
}

sub commandname {
    return lastpathcomponent(commandpath());
}

sub absolutepath {
    my $path = shift;

    assertparameter($path);

    return File::Spec->rel2abs($path);
}

sub lastpathcomponent {
    my $path = shift;

    assertparameter($path);

    return basename($path);
}

sub pathbydeletinglastpathcomponent {
    my $path = shift;

    assertparameter($path);

    return dirname($path);
}

sub pathbyappendingpathcomponents {
    my $path = shift;
    my @components = @_;

    assertparameter($path);

    return pathbyjoiningpathcomponents(pathcomponents($path), @components);
}

sub pathbyjoiningpathcomponents {
    my @components = @_;

    return join("/", @components);
}

sub pathcomponents {
    my $path = shift;

    assertparameter($path);

    return split(/\//, $path);
}

sub pathextension {
    my $path = shift;

    assertparameter($path);

    if($path =~ /^(.+)\.(\w+)$/) {
        return $2;
    } else {
        return $path;
    }
}

sub pathbydeletingpathextension {
    my $path = shift;

    assertparameter($path);

    if($path =~ /^(.+)\.(\w+)$/) {
        return $1;
    } else {
        return $path;
    }
}

sub pathbyappendingpathextensions {
    my $path = shift;
    my @extensions = @_;

    assertparameter($path);

    my $extension = join(".", @extensions);

    if($path =~ /\.$/) {
        return $path . $extension;
    } else {
        return $path . "." . $extension;
    }
}



# assert

sub asserttrue {
    fatal($_[1] . " (" . _assertcallsitestring() . ")") unless $_[0];
}

sub assertfalse {
    fatal($_[1] . " (" . _assertcallsitestring() . ")") if $_[0];
}

sub assertdefined {
    fatal($_[1] . " (" . _assertcallsitestring() . ")") unless defined($_[0]);
}

sub assertundefined {
    fatal($_[1] . " (" . _assertcallsitestring() . ")") if defined($_[0]);
}

sub assertparameter {
    fatal("Missing parameter (" . _assertcallsitestring() . ")") unless defined($_[0]);
}

sub assertcanrun {
    asserttrue(canrun($_[0]), "Can't run \"$_[0]\"");
}

sub _assertcallsitestring {
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

    println commandname(), ": ", $message;

    exit(1);
}

sub error {
    my $message = shift;

    chomp($message);

    println commandname(), ": ", $message;
}

sub usage {
    my @messages = @_;

    my $message = shift(@messages);

    if($message) {
        println "Usage: ", commandname(), " ", $message;
    } else {
        println "Usage: ", commandname();
    }

    foreach my $eachmessage (@messages) {
        println $eachmessage;
    }

    exit(2);
}

1;
