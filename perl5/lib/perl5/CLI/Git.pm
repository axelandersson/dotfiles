#!/usr/bin/perl -w

package CLI::Git;

use strict;
use feature "state";



# environment

sub gitdirectory {
    our $gitdirectory;

    if(!$gitdirectory) {
        $gitdirectory = CLI::run(["git", "rev-parse", "--git-dir"]);
    }

    return $gitdirectory;
}



# config

our %_CONFIG;

our $CONFIGDEFAULT = "default";
our $CONFIGSYSTEM = "system";
our $CONFIGGLOBAL = "global";
our $CONFIGLOCAL = "local";

sub configset {
    my $key = shift;
    my $value = shift;
    my $domain = shift || $CONFIGDEFAULT;

    CLI::assertparameter($key);
    CLI::assertparameter($value);
    CLI::asserttrue($domain eq $CONFIGSYSTEM || $domain eq $CONFIGGLOBAL || $domain eq $CONFIGLOCAL || $domain eq $CONFIGDEFAULT, "Domain \"$domain\" not supported");

    my @flags;

    if($domain eq $CONFIGSYSTEM) {
        push(@flags, "--system");
    }
    elsif($domain eq $CONFIGGLOBAL) {
        push(@flags, "--global");
    }
    elsif($domain eq $CONFIGLOCAL) {
        push(@flags, "--local");
    }

    CLI::run(["git", "config", @flags, $key, $value]);

    my $config = $_CONFIG{$domain};

    if($config) {
        $config->{$key} = $value;
    }
}

sub configunset {
    my $key = shift;
    my $domain = shift || $CONFIGDEFAULT;

    CLI::assertparameter($key);
    CLI::asserttrue($domain eq $CONFIGSYSTEM || $domain eq $CONFIGGLOBAL || $domain eq $CONFIGLOCAL || $domain eq $CONFIGDEFAULT, "Domain \"$domain\" not supported");

    my @flags;

    if($domain eq $CONFIGSYSTEM) {
        push(@flags, "--system");
    }
    elsif($domain eq $CONFIGGLOBAL) {
        push(@flags, "--global");
    }
    elsif($domain eq $CONFIGLOCAL) {
        push(@flags, "--local");
    }

    CLI::run(["git", "config", "--unset", @flags, $key]);

    my $config = $_CONFIG{$domain};

    if($config) {
        $config->{$key} = undef;
    }
}

sub configget {
    my $key = shift;
    my $domain = shift || $CONFIGDEFAULT;

    CLI::assertparameter($key);
    CLI::asserttrue($domain eq $CONFIGSYSTEM || $domain eq $CONFIGGLOBAL || $domain eq $CONFIGLOCAL || $domain eq $CONFIGDEFAULT, "Domain \"$domain\" not supported");

    my @flags;

    if($domain eq $CONFIGSYSTEM) {
        push(@flags, "--system");
    }
    elsif($domain eq $CONFIGGLOBAL) {
        push(@flags, "--global");
    }
    elsif($domain eq $CONFIGLOCAL) {
        push(@flags, "--local");
    }

    my $config = $_CONFIG{$domain};

    if(!$config) {
        $config = {};
        $_CONFIG{$domain} = $config;
    }

    my $value = $config->{$key};

    if(!$value) {
        $value = CLI::run(["git", "config", "--get", $key]);
        $config->{$key} = $value;
    }

    return $value;
}

sub username {
    return configget("user.name");
}

sub color {
    my $type = shift;

    CLI::assertparameter($type);

    return configget("cli.color.$type");
}



# pager

sub runpager {
    my $input = shift;
    my $options = shift;

    my $pager = $options->{"pager"} || configget("core.pager");

    CLI::run($pager, { "input" => $input });
}



# blame

sub blame {
    my $file = shift;
    my $branch = shift;

    CLI::assertparameter($file);
    CLI::assertparameter($branch);

    my @input = CLI::run(["git", "--no-pager", "blame", "--line-porcelain", $branch, $file]);
    my @output;
    my %data;

    foreach my $line (@input) {
        if($line =~ /^([a-h0-9]{6,40}) (\d+) (\d+)/) {
            $data{"commit"} = $1;
        }
        elsif($line =~ /^(author|author-mail|author-time|author-tz|committer|committer-mail|committer-time|committer-tz|summary|filename) (.+)$/) {
            $data{$1} = $2;
        }
        elsif($line =~ /^(previous) ([a-h0-9]{6,40}) (.*)$/) {
        }
        elsif($line =~ /^\t(.*)$/) {
            $data{"line"} = $1;

            push(@output, { %data });

            %data = ();
        }
    }

    return @output;
}



# log

sub log {
    my $options = shift;

    my @flags;

    if($options->{"maxcount"}) {
        push(@flags, "--max-count", $options->{"maxcount"});
    }

    if($options->{"time"} && $options->{"time"} =~ /^(\-|\+)?(\d+)(h|d|w|m|y)$/) {
        my %units = ("h" => "hour", "d" => "day", "w" => "week", "m" => "month", "y" => "year");

        my $flag = ($1 && $1 eq "+") ? "before" : "after";
        my $number = $2;
        my $unit = ($number == 1) ? $units{$3} : $units{$3} . "s";

        push(@flags, "--$flag", "$number $unit ago");
    }

    if($options->{"patch"}) {
        push(@flags, "--patch");
        push(@flags, "-m");
        push(@flags, "--first-parent");
    }

    if($options->{"stat"}) {
        push(@flags, "--stat");
    }

    if($options->{"grepauthor"} || $options->{"grepmessage"}) {
        push(@flags, "--perl-regexp");

        if($options->{"grepauthor"}) {
            push(@flags, "--author", $options->{"grepauthor"});
        }
        elsif($options->{"grepmessage"}) {
            push(@flags, "--grep", $options->{"grepmessage"});
        }

        if($options->{"grepignorecase"}) {
            push(@flags, "--regexp-ignore-case");
        }
    }

    if($options->{"branch"}) {
        push(@flags, $options->{"branch"});
    }
    elsif($options->{"fromcommit"} && $options->{"tocommit"}) {
        push(@flags, $options->{"fromcommit"} . ".." . $options->{"tocommit"});
    }

    if($options->{"file"}) {
        push(@flags, "--", $options->{"file"});
    }

    my $format = "commit %h%nauthor %an%nauthor-relative %ar%ncommitter %cn%ncommitter-relative %cr%nrefs %C(auto)%d%C(reset)%nsubject %s%nbody start%n%b%nbody stop%n";
    my @input = CLI::run(["git", "--no-pager", "log", "--pretty=tformat:$format", "--no-prefix", @flags], { "assertonerror" => 1 });

    my @output;
    my %data;
    my @body;
    my @content;
    my $state = 0;

    foreach my $line (@input) {
        if($line =~ /^(commit) (.+)$/ && $state != 1) {
            if(%data) {
                if(@content) {
                    if($options->{"patch"}) {
                        $data{"patch"} = [ CLI::trimmedarray(@content) ];
                    } else {
                        $data{"stat"} = [ map { s/^ (.+?)$/$1/; $_; } CLI::trimmedarray(@content) ];
                    }

                    @content = ();
                }

                push(@output, { %data });

                %data = ();
            }

            $data{$1} = $2;
            $state = 0;
        }
        if($line =~ /^(author|author-relative|committer|committer-relative|refs|subject) (.+)$/ && $state != 1) {
            $data{$1} = $2;
        }
        elsif($line =~ /^body start$/ && $state == 0) {
            $state = 1;
        }
        elsif($line =~ /^body stop$/ && $state == 1) {
            if(@body) {
                $data{"body"} = [ map { s/\r//; $_; } CLI::trimmedarray(@body) ];
                @body = ();
            }

            $state = 2;
        }
        elsif($state == 1) {
            push(@body, $line);
        }
        elsif($state == 2) {
            push(@content, $line);
        }
    }

    if(%data) {
        if(@content) {
            if($options->{"patch"}) {
                $data{"patch"} = [ CLI::trimmedarray(@content) ];
            } else {
                $data{"stat"} = [ map { s/^ (.+?)$/$1/; $_; } CLI::trimmedarray(@content) ];
            }
        }

        push(@output, { %data });
    }

    return @output;
}

sub loggraph {
    my $options = shift;

    my @flags;

    if($options->{"maxcount"}) {
        push(@flags, "--max-count", $options->{"maxcount"});
    }

    my $format = "commit(%h) author(%an) author-relative(%ar) subject(%s)";
    my @input = CLI::run(["git", "--no-pager", "log", "--all", "--graph", "--simplify-by-decoration", "--pretty=tformat:$format", @flags], { "assertonerror" => 1 });

    my @output;

    foreach my $line (@input) {
        my %data;

        if($line =~ /^(.+?) commit\((.+?)\) author\((.+?)\) author-relative\((.+?)\) subject\((.+?)\)$/) {
            $data{"graph"} = $1;
            $data{"commit"} = $2;
            $data{"author"} = $3;
            $data{"author-relative"} = $4;
            $data{"subject"} = $5;
        } else {
            $data{"graph"} = $line;
        }

        push(@output, \%data);
    }

    return @output;
}

sub logbranches {
    my @refs = ("refs/heads", "refs/remotes");
    my $format = "ref(%(refname:short)) commit(%(objectname:short)) author(%(authorname)) author-relative(%(authordate:relative)) subject(%(subject))";
    my @input = CLI::run(["git", "--no-pager", "for-each-ref", "--format=$format", @refs], { "assertonerror" => 1 });

    my @output;

    foreach my $line (@input) {
        my %data;

        if($line =~ /^ref\((.+?)\) commit\((.+?)\) author\((.+?)\) author-relative\((.+?)\) subject\((.+?)\)$/) {
            $data{"ref"} = $1;
            $data{"commit"} = $2;
            $data{"author"} = $3;
            $data{"author-relative"} = $4;
            $data{"subject"} = $5;

            push(@output, \%data);
        }
    }

    return @output;
}



# show

sub showfile {
    my $file = shift;
    my $branch = shift;

    CLI::assertparameter($file);
    CLI::assertparameter($branch);

    return CLI::run(["git", "--no-pager", "show", "$branch:./$file"], { "assertonerror" => 1 });
}

sub showcommit {
    my $commit = shift;
    my $options = shift;

    CLI::assertparameter($commit);

    my @flags;

    if($options->{"patch"}) {
        push(@flags, "--patch");
    }

    if($options->{"stat"}) {
        push(@flags, "--stat");
    }

    if($options->{"raw"}) {
        push(@flags, "--no-color");
    }

    my $format = "author %an%nauthor-email %ae%n%nauthor-date %ad%ncommitter %cn%ncommitter-email %ce%ncommitter-date %cd%nrefs %C(auto)%D%C(reset)%ncommit %H%nparents %P%ntree %T%nsubject %s%nbody start%n%b%nbody stop";
    my @input = CLI::run(["git", "--no-pager", "show", "--no-prefix", "--pretty=format:$format", @flags, $commit], { "assertonerror" => 1 });

    my %data;
    my @body;
    my @content;
    my $state = 0;

    foreach my $line (@input) {
        if($line =~ /^(author|author-email|author-date|committer|committer-email|committer-date|refs|commit|parents|tree|subject) (.*)$/ && $state != 1) {
            $data{$1} = $2;
        }
        elsif($line =~ /^body start$/ && $state == 0) {
            $state = 1;
        }
        elsif($line =~ /^body stop$/ && $state == 1) {
            $data{"body"} = [ map { s/\r//; $_ } CLI::trimmedarray(@body) ];

            $state = 2;
        }
        elsif($state == 1) {
            push(@body, $line);
        }
        elsif($state == 2) {
            push(@content, $line);
        }
    }

    if($options->{"patch"}) {
        $data{"patch"} = [ CLI::trimmedarray(@content) ];

        if($data{"parents"} && !@{$data{"patch"}}) {
            my @parents = split(/ /, $data{"parents"});

            if(@parents == 2) {
                my @diffinput = CLI::run(["git", "--no-pager", "diff", "--no-prefix", $parents[0] . "..." . $parents[1]], { "assertonerror" => 1 });

                $data{"patch"} = [ CLI::trimmedarray(@diffinput) ];
            }
        }
    }
    elsif($options->{"stat"}) {
        $data{"stat"} = [ map { s/^ (.+?)$/$1/; $_; } CLI::trimmedarray(@content) ];
    }

    CLI::assertdefined($data{"commit"}, "Invalid output from \"git show\" for $commit");

    return \%data;
}



# diff

sub diff {
    my $options = shift;

    my $command = $options->{"tool"} ? "difftool" : "diff";
    my @flags;

    if($options->{"raw"}) {
        push(@flags, "--color=never", "--no-textconv");
    }

    if($options->{"staged"}) {
        push(@flags, "--staged");
    }

    if($options->{"revision"}) {
        push(@flags, $options->{"revision"});
    }

    if($options->{"file"}) {
        push(@flags, "--", $options->{"file"});
    }

    return CLI::run(["git", "--no-pager", $command, @flags], { "assertonerror" => 1 });
}



# branches

sub branches {
    state @branches;

    if(!@branches) {
        @branches = CLI::run(["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"], { "assertonerror" => 1 });
    }

    return @branches;
}

sub branch {
    state $branch;

    if(!$branch) {
        $branch = CLI::run(["git", "rev-parse", "--abbrev-ref", "HEAD"], { "assertonerror" => 1 });
    }

    return $branch;
}

sub remotebranch {
    my $branch = shift || branch();

    if($branch !~ /^origin/) {
        my $remote = configget("branch.$branch.remote");

        if($remote) {
            return "$remote/$branch";
        }
    }

    return undef;
}

sub isbranch {
    my $branch = shift;

    return 0 unless $branch;

    return 1 if grep { $_ eq $branch } branches();

    return 0;
}



# commits

sub shortcommit {
    my $commit = shift;
    state %commits;

    CLI::asserttrue(iscommit($commit), "Commit \"$commit\" not supported");

    my $shortcommit = $commits{$commit};

    if(!$shortcommit) {
        $shortcommit = CLI::run(["git", "rev-parse", "--short", $commit]);
        $commits{$commit} = $shortcommit;
    }

    return $shortcommit;
}

sub iscommit {
    my $commit = shift;

    return 0 unless $commit;

    if($commit =~ /^(.+?)(\@|\^|\~)(.+?)?$/) {
        $commit = $1;
    }

    return 1 if $commit =~ /^[a-f0-9]{6,40}$/;
    return 1 if $commit eq "HEAD";
    return 1 if isbranch($commit);

    return 0;
}

sub iscommitrange {
    my $range = shift;

    return 0 unless $range;

    if($range =~ /^([a-f0-9]{6,40})\.\.([a-f0-9]{6,40})$/) {
        return 1;
    }

    return 0;
}


sub commitrange {
    my $range = shift;

    return undef unless $range;

    if($range =~ /^([a-f0-9]{6,40})\.\.([a-f0-9]{6,40})$/) {
        return ($1, $2);
    }

    return undef;
}



# formatting

sub commitstring {
    my $commit = shift;

    CLI::assertparameter($commit);

    my $color = color("commit") || "cyan,none,none";

    return CLI::coloredstring($commit, $color);
}

sub refstring {
    my $ref = shift;

    CLI::assertparameter($ref);

    if($ref =~ /^origin/) {
        my $color = color("remoteref") || "red,none,none";

        return CLI::coloredstring($ref, $color);
    } else {
        my $color = color("localref") || "blue,none,none";

        return CLI::coloredstring($ref, $color);
    }
}

sub authorstring {
    my $author = shift;

    CLI::assertparameter($author);
    
    my $color = color("author") || "magenta,none,none";

    return CLI::coloredstring($author, $color);
}

sub emailstring {
    my $email = shift;

    CLI::assertparameter($email);

    my $color = color("email") || "none,none,none";

    return CLI::coloredstring("<$email>", $color);
}

sub datestring {
    my $date = shift;

    CLI::assertparameter($date);

    my $color = color("date") || "none,none,none";

    return CLI::coloredstring($date, $color);
}

sub subjectstring {
    my $subject = shift;

    CLI::assertparameter($subject);

    my $color = color("subject") || "white,none,none";

    return CLI::coloredstring($subject, $color);
}

sub bodystring {
    my $body = shift;

    CLI::assertparameter($body);

    my $color = color("body") || "white,bold,none";

    return CLI::coloredstring($body, $color);
}

sub blameauthorstring {
    my $author = shift;

    CLI::assertparameter($author);

    my $color = color("blameauthor") || "magenta,none,black";

    return CLI::coloredstring($author, $color);
}

sub blamedatestring {
    my $date = shift;

    CLI::assertparameter($date);

    my $color = color("blamedate") || "none,none,black";

    return CLI::coloredstring($date, $color);
}

sub blamecommitstring {
    my $commit = shift;

    CLI::assertparameter($commit);

    my $color = color("blamecommit") || "cyan,none,black";

    return CLI::coloredstring($commit, $color);
}

1;
