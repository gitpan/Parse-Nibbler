package Parse::Nibbler;

# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

## See POD after __END__


require 5.005_62;
use strict;
use warnings;

our $VERSION = '1.00';


use Carp;
use Data::Dumper;

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

###############################################################################
sub Register
###############################################################################
{
  my ($rulename, $coderef) = @_;

  my ($calling_package) = caller;


  print "registering rule $rulename in package $calling_package \n" if ($main::DEBUG);

  no strict;

  my $pkg_rule = $calling_package.'::'.$rulename;

  *{$pkg_rule} = 
    sub 
      {
	my $p = shift(@_);
	my $rule_quantifier = shift(@_);
	$rule_quantifier = '' unless(defined($rule_quantifier));

	my ($min, $max, $separator);

	# quantity is specified via {min:max} syntax
	if( $rule_quantifier =~ s/(\{.+\})// )
	  {
	    my $qty=$1;
	    $qty =~ s/\s//g;
	
	    # {3} means exactly 3
	    if( $qty =~ /\{(\d+)\}/ )
	      {
		$min = $1;
		$max = $min;
	      }

	    # {3:} means 3 or more
	    elsif ( $qty =~ /\{(\d+)\:\}/ )
	      {
		$min = $1;
	      }

	    # {3:5} means 3 to 5, inclusive
	    elsif ( $qty =~ /\{(\d+)\:(\d+)\}/ )
	      {
		$min = $1;
		$max = $2
	      }
	  }
	else
	  {
	    $min = 1;
	    $max = 1;
	  }

	# separator for a list is specified with /separator/
	# currently, it MUST be a string literal.
	# i.e. cant use another rule to define a separator.
	# also, separator cannot contain whitespace or be a null string
	if ($rule_quantifier =~ s/\/(.+)\///)
	  {
	    $separator = $1;
	    if($separator =~ /\s/)
	      {
		die ("separator /$separator/ cannot contain whitespace");
	      }
	    if(length($separator) == 0)
	      {
		die ("separator of length zero is not supported");
	      }
	  }

	# if there is anything else in the quantifier, 
	# we don't know how to handle it.
	
	$rule_quantifier =~ s/\s//g;
	if($rule_quantifier)
	  {
	    die("'$pkg_rule' called with unknown quantifier $rule_quantifier");
	    # should probably use caller() to print out who called this rule
	    # what file, what line number, etc.
	  }

	print "AAA rule: $pkg_rule,          parser is ". Dumper $p if ($main::DEBUG);

	# create an array to contain the results of this rule
	my $this_rule_results = [];
	my $first_rule = 0;
	if(!(exists($p->{list_of_rules_in_progress})))
	  {
	    $p->{list_of_rules_in_progress} = [$this_rule_results];
	    push(@{$p->{list_of_rules_in_progress}}, $this_rule_results);
	    $first_rule = 1;
	  }
	else
	  {
	    push(@{$p->{list_of_rules_in_progress}->[-1]}, $this_rule_results);
	    push(@{$p->{list_of_rules_in_progress}}, $this_rule_results);
	  }

	#######################################################
	# check the acceptable quantity of rules are present
	#######################################################
	my $eval_error='';
	my $rule_succeeded=0;
	my $rules_found=0;

	while(1)
	  {
	    eval
	      {
		$rule_succeeded=&$coderef($p, @_);
	      };

	    if($@)
	      {
		$eval_error = $@;
		last;
	      }

	    $rules_found++;

	    if ( (defined($max)) and ($rules_found >= $max) )
	      {
		last;
	      }

	    # now look for a separator
	    if(defined($separator))
	      {
		eval
		  {
		    $p->ValueIs($separator);
		  };

		if($@)
		  {
		    $eval_error = $@ if $p->ErrorIsEndOfFile;
		  }
	      }
	  }

	print "BBB rule: $pkg_rule,  eval is $eval_error parser is ". Dumper $p if ($main::DEBUG);

	#check to see if we met the minimum requirement
	# if we did, any eval errors (except EOF) can be ignored
	if($rules_found>=$min)
	  {
	    $eval_error = '' unless( $p->ErrorIsEndOfFile );
	  }

	elsif(!($eval_error))
	  {
	    $eval_error =  "not enough rules ($pkg_rule) for quantifiers";
	  }
	print "CCC rule: $pkg_rule,  eval is $eval_error \n" if ($main::DEBUG);


	# no matter what, pop the top off the current rule array.
	# want current rule to revert to previous rule.
	my $pop = pop(@{$p->{list_of_rules_in_progress}});

	print "DDD rule: $pkg_rule,  eval is $eval_error parser is ". Dumper $p if ($main::DEBUG);

	# check to see if this rule passed or failed.
	my $ret;

	if ( 
	    (
	     (!($rule_completed)) 
	     and  
	     (($eval_error) and ($eval_error!~/EOF/))
	    )
	   )
	  {
	    # if failed, pop the current rule out of the end of the previous rule.
	    $p->PutRuleContentsInBoneYard($this_rule_results);
	    $this_rule_results = undef;
	    if(
	       (ref($p->{list_of_rules_in_progress}) eq 'ARRAY')
	       and
	       (ref($p->{list_of_rules_in_progress}->[-1]) eq 'ARRAY')
	      )
	      {
		pop(@{$p->{list_of_rules_in_progress}->[-1]});
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

	$p->FlagEndOfFile if ( defined($eval_error) and ($eval_error =~ /EOF/) ) ;
	return $ret;
      }

}


#############################################################################
#############################################################################
# create a new parser with:  my $obj = P->new;
#############################################################################
#############################################################################
sub new	
#############################################################################
{
	my $pkg = shift;
	my $filename = shift;

	open(my $handle, $filename) or confess "Error opening $filename \n";

	my $obj =
	  {
	   filename=>$filename,
	   handle=>$handle,
	   current_line=>'',
	   line_number => 0,

	  };

	bless $obj, $pkg;

}

#############################################################################
# Lexer
# a rudimentary lexer
# your higher level module should overload this subroutine.
# it is provided here for simple, rudimentary lexing.
#############################################################################
sub Lexer
#############################################################################
{
  my $p = shift;

  while(1)
    {
      my $line = $p->{line_number};
      my $col = pos($p->{current_line});

      # if at end of line
      if( 
	 ( length($p->{current_line}) == 0 )
	 or
	 ( length($p->{current_line}) == pos($p->{current_line}) )
	 )
	{
	  $p->{line_number} ++;
	  my $fh = $p->{handle};
	  $p->{current_line} = <$fh>;
	  return undef unless(defined($p->{current_line}));
	  chomp($p->{current_line});
	  pos($p->{current_line}) = 0;
	  redo;
	}

      # delete any leading whitespace and check it again
      if( $p->{current_line} =~ /\G\s+/gc) 
	{
	  redo;
	}

      # look for comment to end of line
      if($p->{current_line} =~ /\G\#.*/gc)
	{
	  redo;
	}

      if ($p->{current_line} =~ /\G([a-zA-Z]\w*)/gc) 
	{
	  return bless 
	    [ 'Identifier', $1, $line, $col ],
	      'Lexical';
	}

      if ($p->{current_line} =~ /\G(\d+)/gc)
	{
	  return bless [ 'Digits', $1, $line, $col ],
	      'Lexical';
	}

      $p->{current_line} =~ /\G(.)/gc;

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
  my ($p,$msg) = @_;
  eval
    {
      $p->RuleFailed($msg);
    };
  print $@;
  exit;
}


###############################################################################
sub RuleFailed
###############################################################################
{
    my ($p,$msg) = @_;

    die ($msg . "\n" );
}


###############################################################################
sub FlagEndOfFile
###############################################################################
{
  my ($p) = @_;
  die ("EOF MATES\n" );
}

###############################################################################
sub ErrorIsEndOfFile
###############################################################################
{
  my ($p) = @_;
  if ( defined($@) and ($@=~/EOF/) )
    {return 1;}
  else
    {return 0;}
}

###############################################################################
sub GetItem
###############################################################################
{
  my ($p) = @_;

  my $item;
  if(
     (ref($p->{lexical_boneyard}) eq 'ARRAY')
     and
     (scalar(@{$p->{lexical_boneyard}}))
     )
    {
      $item = pop(@{$p->{lexical_boneyard}});
    }
  else
    {
      $item = $p->Lexer;
    }

  $p->FlagEndOfFile unless(defined($item));

  return $item;
}
###############################################################################

###############################################################################
sub PutItemInCurrentRule
###############################################################################
{
    my ($p,$item) = @_;

    if(ref($p->{list_of_rules_in_progress}->[-1]) eq 'ARRAY')
      {
	push(@{$p->{list_of_rules_in_progress}->[-1]}, $item );
      }
    else
      {
	push(@{$p->{list_of_rules_in_progress}}, $item );
      }
}


###############################################################################
sub PutItemInBoneYard
###############################################################################
{
    my ($p,$item) = @_;

    push(@{$p->{lexical_boneyard}}, $item );
}

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
	  $p->PutItemInBoneYard( $item );
	}
    }


}


###############################################################################
sub TypeIs
###############################################################################
{
  my ($p, $type) = @_;

  my $item = $p->GetItem;

  if($item->[0] eq $type)
    {
      $p->PutItemInCurrentRule( $item );
      return 1;
    }
  else
    {
      $p->PutItemInBoneYard( $item );
      $p->RuleFailed("Expected type '$type'");
      return 0;
    }
}

###############################################################################
sub ValueIs
###############################################################################
{
  my ($p, $value) = @_;

  my $item = $p->GetItem;

  if($item->[1] eq $value)
    {
      $p->PutItemInCurrentRule( $item );
      return 1;
    }
  else
    {
      $p->PutItemInBoneYard( $item );
      $p->RuleFailed("Expected value '$value'");
      return 0;
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
	$p->PutItemInCurrentRule( $item );
	return 1;
      }
    }

  $p->PutItemInBoneYard( $item );
  $p->RuleFailed("Expected one of " . join(' | ', @_) . "\n" );
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
      unless($p->can($alternate))
	{
	  $p->FatalError
	    (
	     "Can't locate parser rule \"$alternate\" via ".
	     "package \"".ref($p)."\""
	    );
	}
    }

  foreach my $alternate (@rules)
    {
      $@ = '';
      print "\ntrying rule alternate $alternate \n" if ($main::DEBUG);
      my $arguments = '';
      if($alternate =~ s/\((.+)\)//)
	{
	  $arguments = $1;
	}

      my $success=0;

      no strict;
      $success = $p -> $alternate ( $arguments );

       return 1 if($success);

      # if rule call is NOT wrapped in an eval block
      # then any exception raised during rule will
      # automatically escalate to top rule.
      # dont need to check for special EOF case here.
      #if( ($@) and ($@ =~ /EOF/) )
      #{
      #  $p->RuleFailed($@);
      #  return 0;
      #}

    }

  $p->RuleFailed("Expected one of " . join(' | ', @_) . "\n" );
  return 0;

}

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
    my $p = shift;
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
    my $p = shift;
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
This method is provided by the Parse::Nibbler module and should not be overridden.



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



A rule is a code reference with a given string name that have been passed to Register.
Here is an example of a rule:


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


This code registers a rule called "MedicalDiagnosis". It uses some builtin methods,
but it also calls the rule just registered, "Name".

Once a user defines a rule, they can use it in other rules by simply calling it
as they would call a method.

Rules registered with the Parse::Nibbler module can be called with quantifiers.
Quantifiers allow you to specify the quantity of rules present.
Quantifiers also allow you to specify whether multiple rules have separators.

Quantifiers are specified using the following string format:

     {min:max}

if a single value is specified with no colon, then the number of matches must
equal the given number exactly.

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



Additional Parse::Nibbler methods are provided to simplify rule definition and
to provide smart, automatic error handling, etc. You grammars should only 
call other rules that you defined, or these methods explained below.

(Note: these methods do not take quantifiers)

----------------
Method: ValueIs
----------------

Parameters: One parameter, required. A string containing the expected value.

Example: $p->ValueIs( 'stringvalue' );

Description: 

This method will look at the next lexical and determine if its value matches
that of the stringvalue given as a parameter. If it does not match, an exception
is raised and the rule fails.

If the values do match, then the parser stores the lexical, and the rule continues.



-----------------------
Method: AlternateValues
-----------------------

Parameters: A list of string parameters, at least two values. 

Example: $p-AlternateValues( 'value1', 'value2' );

Description:

This method behaves like the ValueIs method, except that it will 
recieve a list of allowed alternate expected values. The first match
that succeeds causes the rule to pass and return.

If no match occurs, then an exception is raised and the rule aborts.

If a match does occur, the parser stores the lexical, and the rule continues.



--------------
Method: TypeIs
--------------

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


----------------------
Method: AlternateRules
----------------------

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


=head2 EXPORT

     Register, used to register the rules in your grammar.


=head1 AUTHOR


Copyright (c) 2001 Greg London. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

contact the author via http://www.greglondon.com


=head1 SEE ALSO


=cut
