package Parse::Nibbler;

=for

    Parse::Nibbler - Parse huge files using grammars written in pure perl.
    Copyright (C) 2001  Greg London

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut


## See POD after __END__


require 5.005_62;
use strict;
use warnings;

our $VERSION = '1.08';


use Carp;
use Data::Dumper;

use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );


use constant list_of_rules_in_progress => 0;
use constant line_number => 1;
use constant current_line => 2;
use constant handle => 3;
use constant lexical_boneyard => 4;
use constant filename => 5;


#############################################################################
#############################################################################
#
# class data
#
#############################################################################
#############################################################################

require Exporter;

our @ISA = qw( Exporter );

our @EXPORT = qw( Register );

our %timer_information;
our %caller_counter;

###############################################################################
# Register is an exported subroutine.
# It takes a string ($rulename) and a subroutine reference ($coderef)
# as its input parameters.
# Register determines the current package from where it is called,
# and installs a subroutine with the name $rulename in that package.
# The subroutine executes code that contains a wrapper around the coderef given.
# Register is a class method.
###############################################################################
sub Register
###############################################################################
{
  my ($rulename, $coderef, $saveref) = @_;

  my ($calling_package) = caller;

  print "registering rule $rulename in package $calling_package \n" if ($main::DEBUG);
  my $pkg_rule = $calling_package.'::'.$rulename;

      __register_long($pkg_rule, $coderef);

}


###############################################################################
sub __register_long
###############################################################################
{
  my ($pkg_rule, $coderef) = @_;

  no strict;
  *{$pkg_rule} = 
    sub 
      {
	my $p = $_[0];
	my $rule_quantifier = $_[1];

	my ($min, $max, $separator);

	if(!(defined($rule_quantifier)))
	  {
	    $min = 1;
	    $max = 1;
	    $rule_quantifier='';
	  }
	# quantity is specified via {xxx} syntax
	elsif( $rule_quantifier =~ s/\{(.+)\}// )
	  {
	    my $qty=$1;
	
	    # {?} means 0 or 1,
	    if ( $qty eq '?' )
	      {
		$min = 0;
		$max = 1;
	      }
	    # {+} means 1 or more,
	    elsif ( $qty eq '+' )
	      {
		$min = 1;
	      }
	    # {*} means 0 or more,
	    elsif ( $qty eq '*' )
	      {
		$min = 0;
	      }
	    # {3} means exactly 3
	    elsif( $qty =~ /^(\d+)$/ )
	      {
		$min = $1;
		$max = $min;
	      }
	    # {3:} means 3 or more
	    elsif ( $qty =~ /^(\d+)\:$/ )
	      {
		$min = $1;
	      }
	    # {3:5} means 3 to 5, inclusive
	    elsif ( $qty =~ /^(\d+)\:(\d+)$/ )
	      {
		$min = $1;
		$max = $2;
	      }
	    else
	      {
		$p->FatalError("$pkg_rule called with unknown quantifier {$qty}");
	      }
	  }
	else # could define a separator value with no numeric quantifier.
	  {
	    $min = 1;
	    $max = 1;
	  }

	# separator for a list is specified with /separator/
	# currently, it MUST be a string literal.
	# i.e. cant use another rule to define a separator.
	# note: separator must be a SINGLE item returned by lexer.
	# if lexer returns // as two individual things, then
	# you can't use it as a separator, since comparison will always fail.
	# also, separator cannot contain whitespace or be a null string.
	# i.e. if you want a weird separator, write your lexer to detect it
	# and return it as an atomic unit.
	if ($rule_quantifier =~ s/\/(.+)\///)
	  {
	    $separator = $1;
	  }

	# if there is anything else in the quantifier,
	# we don't know how to handle it.
	if($rule_quantifier)
	  {
	    $p->FatalError
	      ("'$pkg_rule' called with unknown quantifier '$rule_quantifier'");
	    # should probably use caller() to print out who called this rule
	    # what file, what line number, etc.
	  }

	print "AAA rule: $pkg_rule,          parser is ". Dumper $p if ($main::DEBUG);

	# create an array to contain the results of this rule
	my $this_rule_results = [];

	push(@{$p->[list_of_rules_in_progress]->[-1]}, $this_rule_results);
	push(@{$p->[list_of_rules_in_progress]}, $this_rule_results);

	#######################################################
	# check the acceptable quantity of rules are present
	#######################################################
	my $eval_error='';
	my $rules_found=0;

	while(1)
	  {
	    eval
	      {
		&$coderef($p);
		$rules_found++;
	      };

	    if($@)
	      {
		$p->DieOnFatalError;
		$eval_error = $@;
		last;
	      }

	    last if ( (defined($max)) and ($rules_found >= $max) );

	    # now look for a separator
	    if(defined($separator))
	      {
		eval
		  {
		    $p->ValueIs($separator);
		  };

		$p->DieOnFatalError if ($@);
	      }
	  }

	print "BBB rule: $pkg_rule,  eval is $eval_error parser is ". Dumper $p if ($main::DEBUG);

	if( $rules_found >= $min )
	  {
	    $eval_error = '';
	  }

	elsif(length($eval_error)==0)
	  {
	    eval
	      {
		$p->ThrowRule("not enough rules ($pkg_rule) for quantifiers");
	      };

	    $eval_error = $@ ;
	  }

	print "CCC rule: $pkg_rule,  eval is $eval_error \n" if ($main::DEBUG);

	# no matter what, pop the top off the current rule array.
	# want current rule to revert to previous rule.
	pop(@{$p->[list_of_rules_in_progress]});

	print "DDD rule: $pkg_rule,  eval is $eval_error parser is ". Dumper $p if ($main::DEBUG);

	# check to see if this rule passed or failed.
	my $ret;

	if ($eval_error)
	  {
	    # if failed, pop the current rule out of the end of the previous rule.
	    $p->PutRuleContentsInBoneYard($this_rule_results);
	    $this_rule_results = undef;
	    if(
	       (ref($p->[list_of_rules_in_progress]) eq 'ARRAY')
	       and
	       (ref($p->[list_of_rules_in_progress]->[-1]) eq 'ARRAY')
	      )
	      {
		pop(@{$p->[list_of_rules_in_progress]->[-1]});
	      }
	    $ret =  0;
	  }
	else
	  {
	    my $package_for_blessing = $pkg_rule;
	    if(
	       (
		(scalar(@$this_rule_results)>1) and 
		( ($min > 1) or (!(defined($max))) or ($max > 1) )
	       )
	      or
	       (defined($separator))
	      )
	      {
		$package_for_blessing=
		  "Parse::Nibbler::ListOfRules($pkg_rule";

		if(defined($separator))
		  {
		    $package_for_blessing .= ", /$separator/";
		  }

		$package_for_blessing .= ")";

	      }
	    bless($this_rule_results, $package_for_blessing);
	    $ret = 1;
	  }
	print "EEE rule: $pkg_rule, eval is $eval_error parser is ". Dumper $p if ($main::DEBUG);

	$p->ThrowRule($eval_error) if ( ($eval_error) );
	return $ret;
      }
}







#############################################################################
#############################################################################
# create a new parser with:  my $obj = Pkg->new($filename);
# Where 'Pkg' is a package that defines the grammar you wish to use
# to parse the text in question.
# The constructor must be given a filename to start parsing.
# new is a class method.
#############################################################################
#############################################################################
sub new	
#############################################################################
{
	my $pkg = $_[0];
	my $filename = $_[1];

	open(my $handle, $filename) or confess "Error opening $filename \n";

	my $p = [];

	$p->[filename] = $filename;
	$p->[handle] = $handle;
	$p->[current_line] = '';
	pos($p->[current_line])=0;
	$p->[line_number] = 0;
	$p->[lexical_boneyard] = [];

	my $start_rule=[];
	$p->[list_of_rules_in_progress] = [$start_rule];
	push(@{$p->[list_of_rules_in_progress]}, $start_rule);

	bless $p, $pkg;

}

#############################################################################
#############################################################################
#############################################################################
# The rest of the methods in this file are object level methods.
# The object being operated upon is a parser created with the constructor above.
#############################################################################
#############################################################################
#############################################################################


#############################################################################
# Lexer
# a rudimentary lexer
# your higher level module should overload this subroutine.
# it is provided here for simple, rudimentary lexing.
#############################################################################
sub Lexer
#############################################################################
{
  my $p = $_[0];

  while(1)
    {
      my $line = $p->[line_number];
      my $col = pos($p->[current_line]);

      # if at end of line
      if( 
	 ( length($p->[current_line]) == 0 )
	 or
	 ( length($p->[current_line]) == pos($p->[current_line]) )
	 )
	{
	  $p->[line_number] ++;
	  my $fh = $p->[handle];
	  $p->[current_line] = <$fh>;
	  return undef unless(defined($p->[current_line]));
	  chomp($p->[current_line]);
	  pos($p->[current_line]) = 0;
	  redo;
	}

      # delete any leading whitespace and check it again
      if( $p->[current_line] =~ /\G\s+/gc) 
	{
	  redo;
	}

      # look for comment to end of line
      if($p->[current_line] =~ /\G\#.*/gc)
	{
	  redo;
	}

      if ($p->[current_line] =~ /\G([a-zA-Z]\w*)/gc) 
	{
	  return bless 
	    [ 'Identifier', $1, $line, $col ],
	      'Lexical';
	}

      if ($p->[current_line] =~ /\G(\d+)/gc)
	{
	  return bless [ 'Digits', $1, $line, $col ],
	      'Lexical';
	}

      $p->[current_line] =~ /\G(.)/gc;

      return bless [ $1, $1, $line, $col  ],
	'Lexical';

    }
}


#############################################################################
# FatalError
#############################################################################
sub FatalError
#############################################################################
{
  eval
    {
      $_[0]->ThrowRule($_[1]);
    };
  print $@;
  exit;
}


###############################################################################
sub ThrowRule
###############################################################################
{
  my $msg = $_[1];
  if(substr($msg, 0, 2) eq '!!')
    {substr($msg, 0, 29, '');}
  die ("!!Parse::Nibbler::ThrowRule!!" . $msg . "\n" );
}

###############################################################################
sub DieOnFatalError
###############################################################################
{
  return unless($@);
  my $error = $@;
  unless(substr($error, 0, 2) eq '!!')
    {
      substr($error, 0, 29, '');
      $_[0]->FatalError($error);
    }
}


###############################################################################
sub GetItem
###############################################################################
{
  my $p = $_[0];

  if (scalar(@{$p->[lexical_boneyard]}))
    {
      return  pop(@{$p->[lexical_boneyard]});
    }
  else
    {
      return  $p->Lexer;
    }
}
###############################################################################


#############################################################################
sub PutRuleContentsInBoneYard
#############################################################################
{
  my ($p,$rule) = @_;

  while(scalar(@{$rule}))
    {
      my $item=pop(@{$rule});

      if(ref($item) and (ref($item) ne 'Lexical') )
	{
	  $p->PutRuleContentsInBoneYard($item);
	}
      else
	{
	  #	  $p->PutItemInBoneYard( $item );
	  push(@{$p->[lexical_boneyard]}, $item );

	}
    }
}


###############################################################################
###############################################################################
###############################################################################
###############################################################################
# The following methods are object methods,
# intended to be called within your grammars.
# Use these methods to define the contents of your grammars.
###############################################################################
###############################################################################
###############################################################################
###############################################################################


###############################################################################
sub TypeIs
###############################################################################
{
#  my ($p, $type) = @_;
  my $p=$_[0];

  my $item = $p->GetItem;

  if($item->[0] eq $_[1])
    {
      #                PutItemInCurrentRule 
	push(@{$p->[list_of_rules_in_progress]->[-1]}, $item );

      return 1;
    }
  else
    {
      #             PutItemInBoneYard 
      push(@{$p->[lexical_boneyard]}, $item );

      $p->ThrowRule("Expected type '".$_[1]."'");
      return 0;
    }
}



###############################################################################
sub PeekType
###############################################################################
{
  my $p=$_[0];
  if (scalar(@{$p->[lexical_boneyard]}))
    {
      return  $p->[lexical_boneyard]->[-1]->[0];
    }
  else
    {
      my $item = $p->GetItem;
      push(@{$p->[lexical_boneyard]}, $item );
      return $item->[0];
    }
}



###############################################################################
sub ValueIs
###############################################################################
{
#  my ($p, $value) = @_;
  my $p = $_[0];

  my $item = $p->GetItem;

  if($item->[1] eq $_[1])
    {
      #      $p->PutItemInCurrentRule( $item );
	push(@{$p->[list_of_rules_in_progress]->[-1]}, $item );
      return 1;
    }
  else
    {
      #      $p->PutItemInBoneYard( $item );
      push(@{$p->[lexical_boneyard]}, $item );

      $p->ThrowRule("Expected value '".$_[1]."'");
      return 0;
    }
}




###############################################################################
sub PeekValue
###############################################################################
{
  my $p=$_[0];
  if (scalar(@{$p->[lexical_boneyard]}))
    {
      return  $p->[lexical_boneyard]->[-1]->[1];
    }
  else
    {
      my $item = $p->GetItem;
      push(@{$p->[lexical_boneyard]}, $item );
      return $item->[1];
    }
}



###############################################################################
sub AlternateValues
###############################################################################
{
  my $p = shift(@_);

  my $item = $p->GetItem;
  my $actual_value =  $item->[1];

  foreach my $alternate (@_)
    {
      if ($alternate eq $actual_value)
      {
#	$p->PutItemInCurrentRule( $item );
	push(@{$p->[list_of_rules_in_progress]->[-1]}, $item );
	return 1;
      }
    }

#  $p->PutItemInBoneYard( $item );
  push(@{$p->[lexical_boneyard]}, $item );

  $p->ThrowRule("Expected one of " . join(' | ', @_) . "\n" );
  return 0;
}

###############################################################################
sub AlternateRules
###############################################################################
{
  my $p = shift(@_);
  my @rules = @_;

  foreach my $alternate (@rules)
    {
      $@ = '';

      print "\ntrying rule alternate $alternate \n" if ($main::DEBUG);
      my $arguments = '';
      if($alternate =~ s/\((.+)\)//)
	{
	  $arguments = $1;
	}

      ALTERNATE_RULES : eval
	{
	  no strict;
	  $p -> $alternate ( $arguments );
	};

      $p->DieOnFatalError;

      return 1 if(!($@));
    }

  $p->ThrowRule("Expected one of " . join(' | ', @_) . "\n" );
  return 0;
}

#############################################################################
#############################################################################
#############################################################################



#############################################################################
#############################################################################
#############################################################################
#############################################################################
#############################################################################

1;
__END__

=head1 NAME

Parse::Nibbler - Parse huge files using grammars written in pure perl.

=head1 SYNOPSIS

{
package MyGrammar;

use Parse::Nibbler;
our @ISA = qw( Parse::Nibbler );



###############################################################################
Register
( 'McCoy', sub
###############################################################################
  {
    my $p = $_[0];
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
    my $p = $_[0];
    $p->AlternateValues('Dammit', 'Gadammit');
    $p->Name;
    $p->ValueIs(",");
    $p->ValueIs("Ima");
    $p->ValueIs("doctor");
    $p->ValueIs("not");
    $p->ValueIs("a");
    $p->AlternateValues('Bricklayer', 'Ditchdigger');
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
    my $p = $_[0];
    $p->AlternateValues("He", "She");
    $p->ValueIs("is");
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
    my $p = $_[0];
    $p->AlternateValues( 'Jim', 'Scotty', 'Spock' );

  }
);


} # end package MyGrammar



use Data::Dumper;

###############################################################################
# call the constructor to create a parser
###############################################################################
my $p = MyGrammar->new('transcript.txt');


###############################################################################
# call the top-level rule of the grammar on the parser object
###############################################################################
$p->McCoy;

print Dumper $p;



=head1 DESCRIPTION

Create a parser object using the ->new method.
This method is provided by the Parse::Nibbler module and should not be 
overridden.



The main functionality of the Parse::Nibbler module is the Register subroutine.
This subroutine is used to define the rules of your grammar. The Register 
subroutine takes two parameters: A string and a code reference.

The string is the name of the rule (i.e. the name of the subroutine/method)

The code reference is a reference to the code to execute for this rule.

The Register subroutine will take the code reference, wrap it up in another
subroutine that acts as a closure, and then installs that code reference 
as a subroutine with the name matching the given string.

The wrapper code (the closure) is the same for every rule. The wrapper code
handles quantifiers, calls the rule, and decides what to do based on
the rule passing or failing. 



A rule is a code reference with a given string name that have been passed to 
Register. Here is an example of a rule:


Register 
( 'Name', sub 
  {
    my $p = shift;
    $p->AlternateValues( 'Jim', 'Scotty', 'Spock' );

  }
);


The parser object will always be passed in as the first parameter to your rule.
You must pass this into any further rules or any Parse::Nibbler methods.

In the above example, the rule, "Name" is Registered. "Name" calls one of the 
builtin methods, AlternateValues, defined below. Once a rule is Registered,
other rules can call it:


Register 
( 'MedicalDiagnosis', sub 
  {
    my $p = shift;
    $p->AlternateValues("He's", "She's");
    $p->ValueIs("dead");
    $p->ValueIs(",");
    $p->Name;
    $p->ValueIs("!");
  }
);


This code registers a rule called "MedicalDiagnosis". It uses some builtin 
methods, but it also calls the rule just registered, "Name".

Once a user defines a rule, they can use it in other rules by simply calling it
as they would call a method.

Rules registered with the Parse::Nibbler module can be called with quantifiers.
Quantifiers are passed into the Rule when you call it in your grammar
by passing in a string that matches the format described here.

Quantifiers allow you to specify the quantity of rules present.
Quantifiers also allow you to specify whether multiple rules have separators.

Quantifiers are specified using the following string format:

     {quantifier}


This indicates that there are zero or one Name rules expected:
$p->Name('{?}');

This indicates that there are zero or more Name rules expected:
$p->Name('{*}');

This indicates that there are one or more Name rules expected:
$p->Name('{+}');

This indicates that there are exactly three Name rules expected:
$p->Name('{3}');

This indicates there are 1 to 3 Name rules expected:
$p->Name('{1:3}');

This indicates there are at least 2 Name rules expected:
$p->Name('{2:');

Separators are specified using the following string format:

     /separator/

This indicates 1 or more Name rules, each separated by a comma:

$p->Name('{1:}/,/');

It is the job of the Register function to make sure this additional
functionality is provided transparently and automagically to you.


If you call a rule with no quantifier and no separator,
the rule will assume the quantifier is 1 and there is no separator.



Additional Parse::Nibbler methods are provided to simplify rule definition and
to provide smart, automatic error handling, etc. You grammars should only 
call other rules that you defined, or these methods explained below.

(Note: these methods do not take quantifiers)

###############
Method: ValueIs
###############

Parameters: One parameter, required. A string containing the expected value.

Example: $p->ValueIs( 'stringvalue' );

Description: 

This method will look at the next lexical and determine if its value matches
that of the stringvalue given as a parameter. If it does not match, an 
exception is raised and the rule fails.

If the values do match, then the parser stores the lexical, and the rule
continues.



#######################
Method: AlternateValues
#######################

Parameters: A list of string parameters, at least two values. 

Example: $p-AlternateValues( 'value1', 'value2' );

Description:

This method behaves like the ValueIs method, except that it will 
recieve a list of allowed alternate expected values. The first match
that succeeds causes the rule to pass and return.

If no match occurs, then an exception is raised and the rule aborts.

If a match does occur, the parser stores the lexical, and the rule continues.



##############
Method: TypeIs
##############

Parameters: One parameter, required. A string containing the expected type.

Description: 

This method will look at the next lexical item, and determine if the lexical
type matches the type given as a parameter.

Valid type values depend on the Lexer that you use, but possible values
may include "Identifier" and "Number", etc.

Use this in a case where your rule requires an identifier type, for example,
but it does not care what the name of the identifier is for the rule.

If a match occurs, the parser stores the lexical and the rule continues.

If a match does not occur, an exception is raised, and the rule aborts.


######################
Method: AlternateRules
######################

Parameters: A list of string parameters, at least two.

Example: $p->AlternateRules( 'Rule1', 'Rule2' );

Description:

You can describe rule alternation in your rule by calling this method.
The method takes a list of strings whose string values match the names
of the valid alternate rule names.

In the above example, the McCoy rule is either a declaration of profession
or a medical diagnosis. These are two rules that are defined in the same
package. The AlternateRules method allows you to define multiple rules
that may be valid at the same point in the text.

If a rule in the parameter list succeeds, the AlternateRule method
succeeds, and returns immediately.

If no rule succeeds, an exception is thrown, and the rule aborts.

This rule expects either a "DeclareProfession" rule or a 
"MedicalDiagnosis" rule to be present.

Register
( 'McCoy', sub
  {
    my $p = shift;
    $p->AlternateRules( 'DeclareProfession', 'MedicalDiagnosis' );
  }
);


You can specify quantifiers as part of the alternate rule strings.

    $p->AlternateRules( 'DeclareProfession({+})', 'MedicalDiagnosis' );

The above example indicates that you can have one or more 
DeclareProfession rules OR ALTERNATELY you can have exactly
one MedicalDiagnosis rule.


=head2 EXPORT

     Register, used to register the rules in your grammar.


=head1 AUTHOR


    Parse::Nibbler - Parse huge files using grammars written in pure perl.
    Copyright (C) 2001  Greg London

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    contact the author via http://www.greglondon.com


=head1 SEE ALSO


=cut
