#!/usr/bin/perl -w

package CLI::Git;

use strict;



# config

sub aliases {
    my @input = CLI::run("git config --get-regexp ^alias");
    my %output;

    foreach my $line (@input) {
        if($line =~ /^alias\.(\w+?) (.+)$/) {
            $output{$1} = $2;
        }
    }

    return \%output;
}

sub pager {
    return scalar(CLI::run("git config --get core.pager"));
}

sub username {
    return scalar(CLI::run("git config --get user.name"));
}

sub color {
    my $type = shift;

    CLI::assert_parameter($type);

    return scalar(CLI::run("git config --get cli.color.$type"));
}



# blame

sub blame {
    my $file = shift;
    my $branch = shift;

    CLI::assert_parameter($file);
    CLI::assert_parameter($branch);

    my @input = CLI::run("git --no-pager blame --line-porcelain \"$branch\" \"$file\"");
    my @output;
    my $blame = {};

    foreach my $line (@input) {
        if($line =~ /^([a-h0-9]{6,40}) (\d+) (\d+)/) {
            $blame->{"commit"} = $1;
        }
        elsif($line =~ /^(author|author-mail|author-time|author-tz|committer|committer-mail|committer-time|committer-tz|summary|filename) (.+)$/) {
            $blame->{$1} = $2;
        }
        elsif($line =~ /^(previous) ([a-h0-9]{6,40}) (.*)$/) {
        }
        elsif($line =~ /^\t(.*)$/) {
            $blame->{"line"} = $1;

            push(@output, $blame);

            $blame = {};
        }
    }

    return @output;
}



# log

sub log {
    my $flags = shift;
    my $path = shift;

    my $format = "commit %h%nauthor %an%nauthor-relative %ar%nrefs %C(auto)%d%C(reset)%nsubject %s%nbody start%n%b%nbody stop%n";
    my @input = CLI::run("git --no-pager log --pretty=tformat:'$format' " . join(" ", @{$flags}) . " $path");
    my @output;
    my $log;
    my @body;
    my @content;
    my $state = 0;

    foreach my $line (@input) {
        if($line =~ /^(commit) (.+)$/) {
            if($log) {
                if(@content) {
                    my @contentcopy = @content;
                    $log->{"content"} = \@contentcopy;
                    @content = ();
                }

                push(@output, $log);

                $log = {};
            }

            $log->{$1} = $2;
            $state = 0;
        }
        if($line =~ /^(author|author-relative|refs|subject) (.+)$/) {
            $log->{$1} = $2;
        }
        elsif($line =~ /^body start$/ && $state == 0) {
            $state = 1;
        }
        elsif($line =~ /^body stop$/ && $state == 1) {
            if(@body) {
                my @bodycopy = @body;
                $log->{"body"} = \@bodycopy;
                @body = ();
            }

            $state = 2;
        }
        elsif($state == 1) {
            if($line =~ /\w+/) {
                push(@body, $line);
            }
        }
        elsif($state == 2) {
            if($line =~ /\w+/) {
                push(@content, $line);
            }
        }
    }

    if($log) {
        if(@content) {
            my @contentcopy = @content;
            $log->{"content"} = \@contentcopy;
        }

        push(@output, $log);
    }

    return @output;
}

sub log_graph {
    my $flags = shift;

    my $format = "commit(%h) author(%an) author-relative(%ar) subject(%s)";
    my @input = CLI::run("git --no-pager log --all --graph --simplify-by-decoration --pretty=tformat:'$format' " . join(" ", @{$flags}));
    my @output;
    my $log;

    foreach my $line (@input) {
        my $log;

        if($line =~ /^(.+?) commit\((.+?)\) author\((.+?)\) author-relative\((.+?)\) subject\((.+?)\)$/) {
            $log->{"graph"} = $1;
            $log->{"commit"} = $2;
            $log->{"author"} = $3;
            $log->{"author-relative"} = $4;
            $log->{"subject"} = $5;
        } else {
            $log->{"graph"} = $line;
        }

        push(@output, $log);
    }

    return @output;
}

sub log_refs {
    my $refs = shift;

    my @input = CLI::run("git --no-pager for-each-ref --format='ref(%(refname:short)) commit(%(objectname:short)) author(%(authorname)) author-relative(%(authordate:relative)) subject(%(subject))' " . join(" ", @{$refs}));
    my @output;

    foreach my $line (@input) {
        my $log;

        if($line =~ /^ref\((.+?)\) commit\((.+?)\) author\((.+?)\) author-relative\((.+?)\) subject\((.+?)\)$/) {
            $log->{"ref"} = $1;
            $log->{"commit"} = $2;
            $log->{"author"} = $3;
            $log->{"author-relative"} = $4;
            $log->{"subject"} = $5;
        }

        push(@output, $log);
    }

    return @output;
}



# show

sub show_file {
    my $file = shift;
    my $branch = shift;

    CLI::assert_parameter($file);
    CLI::assert_parameter($branch);

    return CLI::run("git --no-pager show $branch:./$file");
}

sub show_commit {
    my $commit = shift;
    my $flags = shift;

    CLI::assert_parameter($commit);

    my $format = "author %an%nauthor-email %ae%n%nauthor-date %ad%ncommitter %cn%ncommitter-email %ce%ncommitter-date %cd%nrefs %C(auto)%D%C(reset)%ncommit %H%nparents %P%ntree %T%nsubject %s%nbody start%n%b%nbody stop";
    my @input = CLI::run("git --no-pager show --pretty=format:'$format' $commit " . join(" ", @{$flags}));
    my $output;
    my @body;
    my @content;
    my $state = 0;

    foreach my $line (@input) {
        if($line =~ /^(author|author-email|author-date|committer|committer-email|committer-date|refs|commit|parents|tree|subject) (.*)$/) {
            $output->{$1} = $2;
        }
        elsif($line =~ /^body start$/ && $state == 0) {
            $state = 1;
        }
        elsif($line =~ /^body stop$/ && $state == 1) {
            if(@body) {
                $output->{"body"} = \@body;
            }

            $state = 2;
        }
        elsif($state == 1) {
            if($line =~ /\w+/) {
                push(@body, $line);
            }
        }
        elsif($state == 2) {
            if($line =~ /\w+/) {
                push(@content, $line);
            }
        }
    }

    if(@content) {
        $output->{"content"} = \@content;
    }

    return $output;
}


# rev-parse

sub rev_parse_head {
    return scalar(CLI::run("git rev-parse --abbrev-ref HEAD"));
}

sub rev_parse_short {
    my $commit = shift;

    CLI::assert_parameter($commit);

    return scalar(CLI::run("git rev-parse --short $commit"));
}



# verification

sub iscommit {
    my $commit = shift;

    return 0 unless $commit;
    return 0 unless $commit =~ /^[a-f0-9]{6,40}$/;

    return 1;
}



sub isbranch {
    my $branch = shift;

    return 0 unless $branch;

    return 1;
}



# colors

sub commitstring {
    my $commit = shift;

    CLI::assert_parameter($commit);

    return CLI::coloredstring($commit, color("commit"));
}

sub localrefstring {
    my $localref = shift;

    CLI::assert_parameter($localref);

    return CLI::coloredstring($localref, color("localref"));
}

sub remoterefstring {
    my $remoteref = shift;

    CLI::assert_parameter($remoteref);

    return CLI::coloredstring($remoteref, color("remoteref"));
}

sub authorstring {
    my $author = shift;

    CLI::assert_parameter($author);

    return CLI::coloredstring($author, color("author"));
}

sub emailstring {
    my $email = shift;

    CLI::assert_parameter($email);

    return CLI::coloredstring("<$email>", color("email"));
}

sub datestring {
    my $date = shift;

    CLI::assert_parameter($date);

    return CLI::coloredstring($date, color("date"));
}

sub subjectstring {
    my $subject = shift;

    CLI::assert_parameter($subject);

    return CLI::coloredstring($subject, color("subject"));
}

sub bodystring {
    my $body = shift;

    CLI::assert_parameter($body);

    return CLI::coloredstring($body, color("body"));
}

sub blameauthorstring {
    my $author = shift;

    CLI::assert_parameter($author);

    return CLI::coloredstring($author, color("blameauthor"));
}

sub blamedatestring {
    my $date = shift;

    CLI::assert_parameter($date);

    return CLI::coloredstring($date, color("blamedate"));
}

sub blamecommitstring {
    my $commit = shift;

    CLI::assert_parameter($commit);

    return CLI::coloredstring($commit, color("blamecommit"));
}

1;
