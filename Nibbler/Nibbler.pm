package Parse::Nibbler;

# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

## See POD after __END__


require 5.005_62;
use strict;
use warnings;

our $VERSION = '0.21';


use Carp;
use Data::Dumper;

#############################################################################
#############################################################################
#
# class data
#
#############################################################################
#############################################################################

#############################################################################
# this array contains a list of all package namespaces that contain rules.
#############################################################################
our @packages;
#############################################################################

#############################################################################
#############################################################################
#
# class subroutines
#
#############################################################################
#############################################################################

#############################################################################
# Register a package namespace with the parser
#############################################################################
sub Register
#############################################################################
{
	croak "don't pass parameters to Register " if (scalar(@_));
	my ($package) = caller;
	print "registering $package \n";
	push(@packages, $package);
}

#############################################################################
sub Bless
#############################################################################
{
	croak "only pass one parameter to Bless " unless(scalar(@_) == 1);

	my $ref = ref($_[0]);
	croak "can only Bless a reference " unless($ref);

	return unless (
		   ($ref eq 'SCALAR')
		or ($ref eq 'ARRAY')
		or ($ref eq 'HASH')
		or ($ref eq 'CODE')
		);

	my ($package) = caller;

	return bless $_[0], $package;	
}

#############################################################################
sub Debug
#############################################################################
{
	no strict;
	PKG : foreach my $pkg (@packages)
		{
		my @symbols;
		my $string = '@symbols = keys(%'.$pkg.'::);';
		eval($string);
		my $found_rule = 0;
		foreach my $symbol (@symbols)
			{
			print "pkg is $pkg, symbol is $symbol\n";
			if($symbol eq 'Rule')
				{
				$found_rule = 1;
				last;
				}

			unless($found_rule)
				{
				warn "no Rule sub in $pkg  \n";
				next PKG;
				}
			}

		my $pkg_qualified_sub_name = $pkg.'::Rule';
		print "pkg_qualified_sub_name is $pkg_qualified_sub_name \n";
		my $code_ref = \&$pkg_qualified_sub_name;



		*{$pkg_qualified_sub_name} = sub
			{
			print "    >" x scalar(@{$_[0]->{pos}});
			print "called $pkg_qualified_sub_name \n";
			my $result = &$code_ref;
			print "    <" x scalar(@{$_[0]->{pos}});
			print $pkg_qualified_sub_name;
			if ($result)
				{
				print " pass \n";
				}
			else
				{
				print " fail \n";
				}
			return $result;
			}
		}


}

INIT
{
	return unless $main::DEBUG;
	Debug();

}


#############################################################################
#############################################################################
# create a new parser with:  my $obj = P->new;
#############################################################################
#############################################################################
# object data:
# 
# all object data is subject to change.
#
# filename -> name of file being read (this is passed into constructor)
# handle -> filehandle of file being read
# string -> current string excerpt from file being parsed
# pos -> an array of string positions.
#		first index is the first position in string being parsed.
#		as you step into sub Rules, you can push a new 'pos' onto
#		this array like a stack. if rule fails, pop off pos.
#		if rule suceeds, shift everything off to end of rule.
# prefix_string -> any string you want to put at start of pattern
#			i.e. if you want to ignore any whitespace that
#			prefixes your token, set this to \s*
#			if you want to be completely explicit in your
#			tokens, set this to ''
# lines_deleted -> indicates how many lines from file have been parsed
#		so far and thrown away. i.e. as file is read in and parsed,
#		successful parsing moves a pointer forward. When pointer
#		gets far enough from beginning of string, the string is
#		deleted from the start of string to the pointer.
#		(this prevents the entire file being stored as a string
#		in memory)
#		The lines_deleted attribute indicates how many lines we've
#		deleted from the string in memory. Current line number is
#		then calculated by lines_deleted + number of lines to current
#		pointer position.
#############################################################################


#############################################################################
# create a new nibbler parser
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
		string=>'', 
		prefix_string=> [ '\s*' ], 
		pos=>[ 0 ], 
		lines_deleted => 0,
		prefix_package => 'Parser::Nibbler::Prefix',
		marker_package => 'Parser::Nibbler::Marker',
		};

	bless $obj, $pkg;

}

#############################################################################
# If we're done processing a large chunk of text, flush it.
#
# i.e. When the first pos pointer has moved quite a bit from the beginning of 
# the string, you can delete the text from start to pos pointer.
#
# this method gets called every m// or s/// operator,
# therefore want to do as little as possible for many calls.
# every once in a while, want to cut off the beginning of the string
# up to where it's been completely parsed, and then create a new string.
# 
# need to update the lines_deleted attribute to indicate how many lines
# were removed from the string.
#############################################################################

sub check_full_belly
{

	if( $_[0]->{pos}->[0] > 5000 )
		{
		my $first_pos = $_[0]->{pos}->[0];

		#############################################################
		# get deleted text so we can count line numbers.
		#############################################################
		my $deleted_text = substr( $_[0]->{string}, 0, $first_pos );

		#############################################################
		# now count number of \n in deleted text and add it to 
		# the lines_deleted attribute.
		#############################################################
		my $n_cnt = 0;
		while($deleted_text =~ /\G\n/g) 
			{ $n_cnt++; }
		
		$_[0]->{lines_deleted} += $n_cnt;

		#############################################################
		# update the string, throw away the old text at beginning.
		#############################################################
		$_[0]->{string} = substr( $_[0]->{string}, $first_pos );

		#############################################################
		# just chopped off the front of the string from 0 to firstpos.
		# need to update all the pos pointers in the array,
		# by subtracting the number of characters we deleted.
		#############################################################
		my $pos;
		foreach $pos (@{$_[0]->{pos}})
			{
			unless($pos=~/\Amarker_/)
				{$pos -= $first_pos;}
			}
		}

}


#############################################################################
# return true if you want to start appending new data from file, 
# else return false
#############################################################################
#
# Note that subroutine keep_appending will allow some hysterisis
# between when you start_appending and when you keep_appending.
#
# The intent is that you append a bunch of text once, do a bunch of matches,
# and then append another bunch of text. every match must check to see
# if it should start appending. the tests for start_appending 
# must be less strict than the tests for keep_appending.
#
# because this is called repeatedly (for EVERY m// or s///),
# want fastest test first, 
# also, once early tests pass, would like following tests to pass
# under "normal" circumstances. 
# (if first test passes, the rest should "fall through")
#
# i.e. if we add 5000 characters, then 
# under most circumstances, we'll have enough lines and enough words.
# the additional testing is only to cover oddball cases where
# we might end up adding 5000 characters of whitespace, and our match
# "bottoms out".  
# i.e. we don't want to hit the end of the string in a m// and fail
# when we would have matched if we had only read more lines from the file.
#
# if your grammar has oddball rules, where all you have is punctuation,
# or whitespace, or some odd thing like that, then you will need to 
# overload this method with another rule that guarantees you will have
# enough text in the string to perform whatever match you may need to perform.
#############################################################################

sub start_filling_plate
{

	# need to append if length of remaining text is less than min required
	return 1 if
	(
		( length($_[0]->{string}) - ($_[0]->{pos}->[-1]) ) 
			< 
		1000
	);

	return 0;
}

sub keep_filling_plate
{

	# need to append if length of remaining text is less than min required
	return 1 if
	(
		( length($_[0]->{string}) - ($_[0]->{pos}->[-1]) ) 
			< 
		5000
	);


	return 0;
}


sub read_block
{
	my $handle = $_[0]->{handle};
	my $line_count = 0;
	while(<$handle>)
		{
		$_[0]->{string} .= $_;
		last if (100 == $line_count++);
		}

}

#############################################################################
# append some more text from file if needed.
# Note that start_filling_plate should have more generous requirements
# than keep_filling_plate. 
# When we detect that we should start_filling_plate, want keep_filling_plate
# to add a lot more text than what start_filling_plate requires.
# that way, once we add a bunch of text, we can do many matches (m//)
# without having to append more text from the file.
# want file reading to be infrequent.
#############################################################################
sub check_empty_plate
{
	if  (Parse::Nibbler::start_filling_plate($_[0]) ) 
		{
		my $handle = $_[0]->{handle};
		until(eof($handle))
			{
			Parse::Nibbler::read_block($_[0]);
			last unless(Parse::Nibbler::keep_filling_plate($_[0]));
			}
		}	
}
	
	
#############################################################################
# check the string, make sure it is ready to do a regular expression.
# 	check_full_belly 
# 	check_empty_plate
#############################################################################
sub check_for_full_belly_or_empty_plate
{
	Parse::Nibbler::check_full_belly($_[0]) ;		 
	Parse::Nibbler::check_empty_plate($_[0]) ;	
}


#############################################################################
# report_error
# call this and pass it a string describing the error.
# if no markers are set, this sub will report the error
# and die.
#
# if the markers are set,
# it is assumed that the grammar is trying something that 
# could fail, in which case, it will just reject the marker,
# and try something else.
#############################################################################
sub report_error
#############################################################################
{
	return if (scalar(keys(%{$_[0]->{marker_hash}})));

	my $err_str = $_[1];
	$err_str = '' unless (defined($err_str));

	my $location = Parse::Nibbler::current_location($_[0]);
	die "Error: ". $err_str. "\n" . $location ;

}



#############################################################################
# this method will return a descriptive string indicating where the parser is
# located in the file. return string may be multi-line,
# especially when parser supports `include statements, etc.
#############################################################################
sub current_location
{
	my $prefix = $_[0]->{prefix_string}->[-1];
	Parse::Nibbler::EatIfSee($_[0], $prefix );
	Parse::Nibbler::See($_[0], '(.*)', my $next_token);


	my $str_to_pos = substr( $_[0]->{string}, 0, $_[0]->{pos}->[-1]);
	print "start pos is xxx". $str_to_pos. "xxx\n";

	# calculate line number in file
	my $string_lines = 1;
	while($str_to_pos=~s/(\A[^\n]*\n)//m)
		{
		print "xxx".$1;
		$string_lines++;
		}

	my $line_number = $_[0]->{lines_deleted} + $string_lines;

	# calculate horizontal position in file:
	$str_to_pos=~s/\t/tttttttt/g;	# replace tabs with 8 characters
	my $vertical_position = length($str_to_pos);

	my $location = 
		"\t".
		"near '$next_token' ".
		"\n".
		"\t".
		"filename:". $_[0]->{filename} ."  ".
		"line:$line_number  ".
		" column:$vertical_position  ".
		"\n";
}


#############################################################################
#
# This is the master method called by all other methods.
#
# this method acts like m/\G$prefix$pattern/mgc on the string.
#
# my $match = $obj->m(pattern);
# my @matches = $obj->m(pattern);
#
# if you want to capture match using parens, 
# and you're only doing one match, then you will need
# to put the $match scalar in list context by putting it in parens.
#
# my ( $match ) = $obj->m('(\w+)');
#
# this is the fastest way to catch a single matching parenthesis.
# the variables $1 and $2 will not be available in your code.
#
#############################################################################
sub _private_match
{
	Parse::Nibbler::check_for_full_belly_or_empty_plate($_[0]);
	my $patt=
		  '\G'
		. $_[0]->{prefix_string}->[-1]
		. $_[1];

	if ($main::DEBUG)
		{
		print "patt is $patt \n" ;
		$_[0]->{string}=~ m/\G\s*(.*)/mgc;
		print "pos is at $1\n";
		print "pos array is : ";
		foreach my $posit (@{$_[0]->{pos}})
			{
			print "$posit, ";
			}
		print "\n";
		}

	pos($_[0]->{string}) = $_[0]->{pos}->[-1];

	#####################################################################
	# do regular expression to see if match was successful.
	# if there are any additional parameters passed in, 
	# then assume they are supposed to receive match values, $1, $2, etc.
	# use eval to get $1, $2, etc values and assign them into @_ ....
	#####################################################################
	my $match_success = $_[0]->{string} =~ m/$patt/mgc;
	my $new_pos = pos( $_[0]->{string} );

	# if there are other arguments in method call, they must be
	# for receiving matches, get matches ($1, $2, ... and assign to @_ ) 
	for(my $iii=2; $iii<scalar(@_); $iii++)
		{
		my $string = '$_['.$iii.'] = $'.($iii-1).';';
		#print "string is $string\n";
		eval($string);
		}

	my $caller_sub = (caller(1))[3];
	$caller_sub =~ s/^.*:://;

	if($match_success)
		{
		if( ($caller_sub eq 'Eat') or ($caller_sub eq 'EatIfSee') )
			{
			$_[0]->{pos}->[-1] = $new_pos;
			}
		}
	else
		{
		if($caller_sub eq 'Eat')
			{
			$_[0]->report_error("expected to eat '".$_[1]."'");
			}
		}

	return $match_success;
}


#############################################################################
#############################################################################
#############################################################################
#############################################################################


sub caller_history
{
	my $history;
	my $i=1;
	while
	( 
		my ($pkg, $file, $line, $subname, $hasargs, $wantarr) =
		caller($i++)
	)
		{
		$wantarr = 'undef' unless(defined($wantarr));
		$history .=
			 "pkg => $pkg, "
			."file => $file, "
			."line => $line, "
			."subname => $subname, "
			."hasargs => $hasargs, "
			."wantarr => $wantarr, "
			."\n";
		}

	return $history;
}


#############################################################################
#
#############################################################################
sub set_marker	# ( my $lexical_marker )
#############################################################################
{
	confess 'set_marker must be called with a lexical variable'
		unless(scalar(@_)==2);

	my $pkg = ref($_[0]);
	confess ' set_marker() is an object method only' unless($pkg);

	my $default_action = 'reject';
	$default_action = $_[1] if (defined($_[1]));

	my $marker_name = "marker_".\$_[1];

	$_[0]->{marker_hash}->{$marker_name}=1;

	my %marker_object;
	$marker_object{action_on_destruct}=$default_action;
	$marker_object{marker_name}=$marker_name;
	$marker_object{parser_object} = $_[0];

	tie $_[1], $_[0]->{marker_package}, \%marker_object;

	push(@{$_[0]->{pos}}, $marker_name);

	# make copy of last position and push it on end of position array
	push(@{$_[0]->{pos}}, $_[0]->{pos}->[-2]);

}



#############################################################################
# 
#############################################################################
sub __accept_named_marker
#############################################################################
{
	my ($package,$filename) = caller;
	unless($filename eq __FILE__)
		{
		confess "__accept_named_marker is a private method\n";
		return 0;
		}

	my $marker_name = $_[1];

	# may have deleted markers out of order 
	# see if it exists in marker_hash
	# if not, ignore this request to accept marker
	unless(exists($_[0]->{marker_hash}->{$marker_name}))
		{
		print "marker already deleted $marker_name \n";
		return ;
		}

	my $last_pos = pop(@{$_[0]->{pos}});
	my $pop_name = '';
	until( $marker_name eq  $pop_name)
		{ 
		$pop_name = pop(@{$_[0]->{pos}});
		if($pop_name =~ /\Amarker_/)
			{delete($_[0]->{marker_hash}->{$pop_name});}
		}

	pop(@{$_[0]->{pos}});

	push(@{$_[0]->{pos}}, $last_pos);
}




#############################################################################
#
#############################################################################
sub __reject_named_marker
#############################################################################
{
	my ($package,$filename) = caller;
	unless($filename eq __FILE__)
		{
		confess "__accept_named_marker is a private method\n";
		return 0;
		}
	my $marker_name = $_[1];

	# may have deleted markers out of order 
	# see if it exists in marker_hash
	# if not, ignore this request to reject marker
	unless(exists($_[0]->{marker_hash}->{$marker_name}))
		{
		print "marker already deleted $marker_name \n";
		return ;
		}

	my $pop_name = '';
	until( $marker_name eq  $pop_name)
		{ 
		$pop_name = pop(@{$_[0]->{pos}});
		if($pop_name =~ /\Amarker_/)
			{delete($_[0]->{marker_hash}->{$pop_name});}
		}

}




#############################################################################
#############################################################################
# want to set a prefix that is local to a rule and all sub-rules.
# when rule is exited, want prefix to revert to whatever it was previously.
# i.e. have it tied to a lexical variable
# push the prefix that the rule wants to enforce,
# when variable goes out of scope, pop the prefix.
#############################################################################
#############################################################################
sub local_prefix    # ( my $lexically_scoped_var, 'prefix_string' )
#############################################################################
{
	confess 'local_prefix must be called with a lexical variable and '.
		'a prefix string'
		unless(scalar(@_)==3);

	my $pkg = ref($_[0]);
	confess ' local_prefix() is an object method only' unless($pkg);


	my $prefix_name = "prefix_".\$_[1];

	$_[0]->{prefix_hash}->{$prefix_name}=1;

	my %prefix_object;
	$prefix_object{prefix_name} = $prefix_name;
	$prefix_object{parser_object} = $_[0];

	push(@{$_[0]->{prefix_string}}, $prefix_name);
	push(@{$_[0]->{prefix_string}}, $_[2]);

	tie $_[1], $_[0]->{prefix_package}, \%prefix_object;


}


sub __pop_last_prefix
{
	my ($package,$filename) = caller;
	unless($filename eq __FILE__)
		{
		confess "__pop_last_prefix is a private method\n";
		return 0;
		}

	my $prefix_name = $_[1];
	unless(exists($_[0]->{prefix_hash}->{$prefix_name}))
		{
		print "prefix already deleted $prefix_name \n";
		return ;
		}

	my $pop_name = '';
	until( $prefix_name eq  $pop_name)
		{ 
		$pop_name = pop(@{$_[0]->{prefix_string}});
		if($pop_name =~ /\Aprefix_/)
			{delete($_[0]->{prefix_hash}->{$pop_name});}
		}


}


#############################################################################
sub Eat
#############################################################################
{
	Parse::Nibbler::_private_match(@_);
}


#############################################################################
sub See
#############################################################################
{
	Parse::Nibbler::_private_match(@_);
}


#############################################################################
sub EatIfSee
#############################################################################
{
	Parse::Nibbler::_private_match(@_);
}


#############################################################################
#############################################################################
#############################################################################
#############################################################################

#############################################################################
# attempt rule and see if it succeeds 
# eat text if succeed, 
# restore pointer if fail.
# return pass or fail
#############################################################################
package Parse::Nibbler::Attempt;
#############################################################################

sub Rule	# ( $object, \&rule, @any_other_arguments)
{
	my $rule_ref = splice(@_, 1,1);

	Parse::Nibbler::set_marker( $_[0], my $rule_marker );
	if (&$rule_ref(@_))
		{
		$rule_marker='accept';
		return 1;
		}
	else
		{
		$rule_marker='reject';
		return 0;
		}
}

#############################################################################
# rule is optional, i.e. 
# 	rule(?)
# eat text if succeed, 
# restore pointer if fail.
# always return SUCCESS.
#############################################################################
package Parse::Nibbler::Optional;	
#############################################################################

sub Rule	# ( $object, \&rule, @any_other_arguments)
{
	my $rule_ref = splice(@_, 1,1);

	Parse::Nibbler::set_marker( $_[0], my $rule_marker );
	if (&$rule_ref(@_))
		{
		$rule_marker='accept';
		return 1;
		}
	else
		{
		$rule_marker='reject';
		return 1;
		}
}


#############################################################################
# zero or more rules, i.e. 
# 	rule(*)
# eat text if succeed, 
# restore pointer if fail.
# always return SUCCESS.
#############################################################################
package Parse::Nibbler::ZeroOrMore;
#############################################################################

sub Rule	# ( $object, \&rule, $scalar)
{
	my $rule_ref = splice(@_, 1,1);

	$_[1] = [];

	while(1)
		{
		Parse::Nibbler::set_marker( $_[0], my $rule_marker );
		&$rule_ref($_[0], my $result) or return 1;
		push(@{$_[1]}, $result);
		$rule_marker = 'accept';
		}
}


#############################################################################
# one or more rules, i.e. 
# 	rule(+)
# eat text if succeed, 
# restore pointer if fail.
# return succeed if at least one rule.
#############################################################################
package Parse::Nibbler::OneOrMore;	
#############################################################################


sub Rule	# ( $object, \&rule, $scalar)
{
	my $rule_ref = splice(@_, 1,1);

	$_[1] = [];


	&$rule_ref($_[0], my $result) or return 0;
	push(@{$_[1]}, $result);
	while(1)
		{
		Parse::Nibbler::set_marker( $_[0], my $rule_marker );
		&$rule_ref($_[0], my $result) or return 1;
		push(@{$_[1]}, $result);
		$rule_marker = 'accept';
		}
}



#############################################################################
# one or more items, separated by commas
# 	rule < , rule >*
# eat text if succeed, 
# restore pointer if fail.
# return succeed if at least one rule.
#############################################################################
package Parse::Nibbler::CommaSeparatedList;	
#############################################################################


sub Rule	# ( $object, \&rule, $scalar)
{
	my $rule_ref = splice(@_, 1,1);

	$_[1] = [];

	&$rule_ref($_[0], my $result) or return 0;
	push(@{$_[1]}, $result);
	while(1)
		{
		if(Parse::Nibbler::EatIfSee($_[0], '\,'))
			{
			Parse::Nibbler::set_marker( $_[0], my $rule_marker );
			&$rule_ref($_[0], my $result) or return 0;
			push(@{$_[1]}, $result);
			$rule_marker = 'accept';
			}
		else
			{
			last;
			}
		}
	return 1;
}




#############################################################################
# one or more items, separated by commas
# the items are optional, so you could have rule, rule, , , rule, rule
# 	rule < , rule? >*
# eat text if succeed, 
# restore pointer if fail.
# return succeed if at least one rule.
#############################################################################
package Parse::Nibbler::CommaSeparatedVoidableList;	
#############################################################################


sub Rule	# ( $object, \&rule, $scalar)
{
	my $rule_ref = splice(@_, 1,1);

	$_[1] = [];

	my $result;
	&$rule_ref($_[0], $result) or return 0;
	push(@{$_[1]}, $result);
	while(Parse::Nibbler::EatIfSee($_[0], '\,'))
		{
		Parse::Nibbler::set_marker( $_[0], my $rule_marker );
		if(&$rule_ref($_[0], $result))
			{$rule_marker = 'accept';}
		push(@{$_[1]}, $result);
		}

	return 1;
}







#############################################################################
#############################################################################
#############################################################################
#############################################################################


#############################################################################
#############################################################################
#############################################################################
#############################################################################
package Parser::Nibbler::Marker;
#############################################################################
#############################################################################
#############################################################################
#############################################################################

#
# markers are tied to this package to get the appropriate behaviour.
# marker can be assigned reject or accept string to force action.
# marker will be rejected when tied scalar goes out of scope.
#

use Carp;
use strict;
use warnings;
use Data::Dumper;

sub TIESCALAR
{
	#print "Creating Marker ".$_[1]->{marker_name}."\n";
	bless $_[1], $_[0];
}


sub DESTROY 
{
	#print "Destroying Marker ".$_[0]->{marker_name}."\n";
	if ($_[0]->{action_on_destruct} eq 'accept')
		{
		Parse::Nibbler::__accept_named_marker
			(
			$_[0]->{parser_object},
			$_[0]->{marker_name}
			);
		}
	else
		{
		Parse::Nibbler::__reject_named_marker
			(
			$_[0]->{parser_object},
			$_[0]->{marker_name}
			);
		}
}

sub FETCH
{
	my $string = "please do not attempt to read set_marker variable";
	warn $string;
	return $string;
}

sub STORE
{

	if ($_[1] eq 'accept')
		{
		$_[0]->{action_on_destruct}='accept';
		}
	elsif($_[1] eq 'reject')
		{
		$_[0]->{action_on_destruct}='reject';
		}
	else
		{
		confess "you can only assign 'accept' or 'reject' to marker"; 
		}

}


1; 

#############################################################################
#############################################################################
#############################################################################
#############################################################################
package Parser::Nibbler::Prefix;
#############################################################################
#############################################################################
#############################################################################
#############################################################################

#
# prefixes are tied to this package to get the appropriate behaviour.
# the prefix is the prefix used in all regular expressions.
# '\G'. prefix ."user pattern"
# you can assign a prefix temporarily, and tie it to this package.
# when tied lexical variable goes out of scope, prefix is reverted to previous.
#


use Carp;
use strict;
use warnings;
use Data::Dumper;

sub TIESCALAR
{
	bless $_[1], $_[0];

}


sub DESTROY 
{
	Parse::Nibbler::__pop_last_prefix
		( $_[0]->{parser_object}, $_[0]->{prefix_name});
}

sub FETCH
{
	my $string = "please do not attempt to read prefix variable";
	warn $string;
	return $string;
}

sub STORE
{
	if(defined( $_[1] ))
		{
		confess "you can only assign undef to a prefix"; 
		return 0;
		}
}


#############################################################################
#############################################################################
#############################################################################
#############################################################################

1;
__END__

=head1 NAME

Parse::Nibbler - Parsing HUGE files a little bit at a time.

=head1 SYNOPSIS

	package VerilogGrammar;


	my $reg = \&Parse::Nibbler::Register;

	# SourceText := description(*)
	package SourceText;

	sub Rule
	{
		Description::Rule($_[0]);
	}

	&$reg;  


	# put the rest of your rules here....

	package main;

	my $parser = VerilogGrammar->new('short.v');

	SourceText::Rule($parser);


=head1 DESCRIPTION

This module is a simple, generic parser designed from the beginning
to parse extremely large files. 

The parser only pulls in a section of the file at a time, (the amount
pulled in is definable on each parser object.)

The module only has three methods for actual parsing:
	Eat
	See
	EatIfSee

All three methods have the same parameter definition.

The first parameter is a string which is used to create a pattern.
The pattern is \G . $object->{prefix_string} . $param1;
This pattern is used to perform a m/$pattern/mgc on the file.

The \G will start the pattern matching where it left off after
the last regular expression.

The prefix attribute is defaulted to \s* so it will skip all
leading whitespace in front of whatever pattern you're looking for.

The remaining parameters can be any quantity, but they return 
any value that would correspond to $1, $2, $3, due to parenthesis
in your pattern. If you don't want to capture anything, don't
put parens in your code, and don't pass in extra parameters.

The return value is true if a match is found, false otherwise.


See t/VerilogGrammar for a working example of a grammar.
 


=head2 EXPORT

None.


=head1 AUTHOR


# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

contact the author via http://www.greglondon.com


=head1 SEE ALSO


=cut
