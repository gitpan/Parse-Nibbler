#!/usr/bin/perl -ws
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use lib "t";
use Data::Dumper;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );

BEGIN
  {
   # use Profiler;
  }

use VerilogGrammar;

my $filename = 't/big_verilog.v';

$filename = shift(@ARGV) if(scalar(@ARGV));


my $start_time = [gettimeofday];

my $p = VerilogGrammar->new($filename);
eval
{
$p->SourceText;
};

print $@;

my $end_time = [gettimeofday];
my $delay_time = tv_interval( $start_time, $end_time);

#### print Dumper $p;

print "delay_time is $delay_time seconds \n";

my $line = $p->{line_number};

print "total number of lines is $line \n";

my $rate = $line / $delay_time;

print "lines per second = $rate \n";


print Dumper \%Parse::Nibbler::timer_information;

print Dumper \%Parse::Nibbler::caller_counter;

print "ok 2\n";
