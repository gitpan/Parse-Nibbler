#!/usr/bin/perl -ws
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use Parse::Nibbler;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use lib "t";
use Data::Dumper;

use VerilogGrammar;

my $filename = 't/verilog.v';

$filename = shift(@ARGV) if(scalar(@ARGV));


my $start = time;

my $p = VerilogGrammar->new($filename);
eval
{
$p->SourceText;
};

print $@;

my $end = time;

print Dumper $p;


my $duration = $end - $start;
$duration = 1 unless($duration);

print "duration is $duration seconds \n";

my $line = $p->{line_number};

print "total number of lines is $line \n";

my $rate = $line / $duration;

print "lines per second = $rate \n";

print "ok 2\n";
