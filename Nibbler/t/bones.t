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

{
package MyGrammar;

use Parse::Nibbler;
our @ISA = qw( Parse::Nibbler );



###############################################################################
Register
( 'McCoy', sub
###############################################################################
  {
    my $p = shift;
    $p->AlternateRules( 'DeclareProfession', 'MedicalDiagnosis' );
  }
);


###############################################################################
# DeclareProfession : 
#    [Dammit,Gadammit] <name> , I'm a doctor not a [Bricklayer,Ditchdigger] !
###############################################################################
Register 
( 'DeclareProfession', sub 
###############################################################################
  {
    my $p = shift;
    $p->AlternateItems('Dammit', 'Gadammit');
    $p->Name;
    $p->ValueIs(",");
    $p->ValueIs("Ima");
    $p->ValueIs("doctor");
    $p->ValueIs("not");
    $p->ValueIs("a");
    $p->AlternateItems('Bricklayer', 'Ditchdigger');
    $p->ValueIs("!");
  }
);

###############################################################################
# MedicalDiagnosis : 
#    [He's,She's] dead, <name> !
###############################################################################
Register 
( 'MedicalDiagnosis', sub 
###############################################################################
  {
    my $p = shift;
    $p->AlternateItems("He's", "She's");
    $p->ValueIs("dead");
    $p->ValueIs(",");
    $p->Name;
    $p->ValueIs("!");
  }
);

###############################################################################
Register 
( 'Name', sub 
###############################################################################
  {
    my $p = shift;
    $p->AlternateItems( 'Jim', 'Scotty', 'Spock' );

  }
);


} # end package MyGrammar

use Data::Dumper;


my $p = MyGrammar->new('t/bones.txt');

$p->McCoy;

print Dumper $p;



print "ok 2\n";
