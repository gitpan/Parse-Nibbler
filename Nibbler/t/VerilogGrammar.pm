package VerilogGrammar;

# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

## See POD after __END__


require 5.005_62;

use strict;
use warnings;
use base Parse::Nibbler;
use Data::Dumper;

our $VERSION = '0.01';

my $reg = \&Parse::Nibbler::Register;

###############################################################################
# SourceText := description(*)
###############################################################################
package SourceText;
###############################################################################

sub Rule
{
	Description::Rule($_[0]);
}

&$reg;  


###############################################################################
# description := module_declaration | primitive_declaration
###############################################################################
package Description;
###############################################################################
sub Rule 
{
	Parse::Nibbler::OneOrMore::Rule
		($_[0], \&ModuleDeclaration::Rule );
}

&$reg;

###############################################################################
package ModuleDeclaration;
###############################################################################

use Data::Dumper;

sub Rule {
	return 0 unless(Parse::Nibbler::EatIfSee($_[0], 'module'));

	my %ModuleDeclaration;
	$ModuleDeclaration{ModuleItem} = [];

	    ModuleName::Rule($_[0], $ModuleDeclaration{ModuleName})
	and Parse::Nibbler::Optional::Rule 
		($_[0], \&ModulePortList::Rule,
		 $ModuleDeclaration{ModulePortList})
	and Parse::Nibbler::Eat($_[0], ';')
	and Parse::Nibbler::ZeroOrMore::Rule
		($_[0], \&ModuleItem::Rule, $ModuleDeclaration{ModuleItem})
	and Parse::Nibbler::Eat($_[0], 'endmodule')
	or return 0;

	print "found module ".$ModuleDeclaration{ModuleName}."\n";
	#print Dumper \%ModuleDeclaration;
	return 1;
}

&$reg;


###############################################################################
package ModuleItem;	#  
###############################################################################

sub Rule 
{
	return 0 if (Parse::Nibbler::See($_[0], 'endmodule'));

	Parse::Nibbler::Attempt::Rule
		($_[0], \&PortDirectionDeclaration::Rule, $_[1]) 
		and return 1;

	Parse::Nibbler::Attempt::Rule
		($_[0], \&ModuleInstantiation::Rule, $_[1])
		and return 1;

}

&$reg;

###############################################################################
package ModuleName;
###############################################################################

sub Rule 
{
	SimpleIdentifier::Rule($_[0], $_[1]);
}

&$reg;

###############################################################################
package ModulePortList;
###############################################################################

sub Rule 
{

	    Parse::Nibbler::EatIfSee( $_[0], '\(' )
	and Parse::Nibbler::CommaSeparatedList::Rule
		( $_[0], \&PortItem::Rule, my $PortItem )
	and Parse::Nibbler::Eat( $_[0], '\)' ) 
	or return 0;

	$_[1] = Parse::Nibbler::Bless $PortItem;
	return 1;
}

&$reg;

###############################################################################
package PortItem;
###############################################################################

sub Rule 
{
	SimpleIdentifier::Rule($_[0], $_[1]);
}

&$reg;

###############################################################################
# call this and pass in a hash.
# the keys will be the names of the ports,
# the data will be the direction
###############################################################################
package PortDirectionDeclaration;
###############################################################################

sub Rule
{
	    Parse::Nibbler::Eat($_[0], '(input|output|inout)', my $direction) 
	and Parse::Nibbler::Optional::Rule($_[0], \&BitSelect::Rule, my $bit)
	and Parse::Nibbler::CommaSeparatedList::Rule
		($_[0], \&SimpleIdentifier::Rule, my $port) 
	and Parse::Nibbler::Eat($_[0], ';')
	or return 0;

	$_[1] = Parse::Nibbler::Bless [ $port , $direction, $bit ];
	return 1;	
}

&$reg;

###############################################################################
# due to ambiguous situations, this should be last thing that we check for.
###############################################################################
package ModuleInstantiation;   
###############################################################################

sub Rule
{
	$_[0]->set_marker( my $mod_inst_marker );

	my %ModuleInstantiation;

	    SimpleIdentifier::Rule($_[0], $ModuleInstantiation{ModuleName} )
	and Parse::Nibbler::OneOrMore::Rule
		($_[0], \&ModuleInstance::Rule,
		$ModuleInstantiation{InstanceList})
	and Parse::Nibbler::Eat($_[0], ';') 
	or return 0;

	$mod_inst_marker = 'accept';
	$_[1] = Parse::Nibbler::Bless \%ModuleInstantiation;

	return 1;
}

&$reg;

###############################################################################
package ModuleInstance;
###############################################################################

sub Rule 
{
	my %ModuleInstance;

	    InstanceName::Rule($_[0], $ModuleInstance{InstanceName}) 
	and Parse::Nibbler::Eat($_[0], '\(' )
	and ModulePortConnections::Rule
		($_[0], $ModuleInstance{ModulePortConnections})
	and Parse::Nibbler::Eat($_[0],  '\)' )
	or return 0;

	$_[1] = Parse::Nibbler::Bless \%ModuleInstance;
}

&$reg;


###############################################################################
package InstanceName;
###############################################################################

sub Rule 
{
	SimpleIdentifier::Rule($_[0], $_[1]);
}

&$reg;


###############################################################################
package ModulePortConnections;
###############################################################################


sub Rule {
	$_[1] = [];

	# check for empty port connection list
	return 1 if ( Parse::Nibbler::See($_[0], '\)') );  

	# is next character is a '.'
	# commit to a named port connection rule.
	# else commit to an ordered port connection rule.
	if(Parse::Nibbler::See($_[0], '\.'))
		{
		return NamedPortConnections::Rule($_[0], $_[1]);
		}

	else					# must be ordered port list
		{
		return OrderedPortConnections::Rule($_[0], $_[1]);
		}

}

&$reg;

###############################################################################
package NamedPortConnections;
###############################################################################

sub Rule 
{
	Parse::Nibbler::See($_[0], '(\.)') or return 0;

	Parse::Nibbler::CommaSeparatedList::Rule
		($_[0], \&NamedPortConnector::Rule, $_[1] ); 
}

&$reg;



###############################################################################
package NamedPortConnector;
###############################################################################

sub Rule 
{
	    Parse::Nibbler::Eat( $_[0], '\.' )
	and SimpleIdentifier::Rule( $_[0],$_[1] )
	and Parse::Nibbler::Eat( $_[0], '\(' )
	and PortConnector::Rule( $_[0],$_[1] )
	and Parse::Nibbler::Eat( $_[0], '\)' );
}

&$reg;




###############################################################################
package OrderedPortConnections;
###############################################################################

sub Rule 
{
	Parse::Nibbler::CommaSeparatedVoidableList::Rule
		($_[0], \&PortConnector::Rule, $_[1] ); 
}

&$reg;

###############################################################################
package PortConnector;
###############################################################################
sub Rule
{
	   Concatenation::Rule($_[0],$_[1])
	or Signal::Rule($_[0],$_[1]);
}

&$reg;



###############################################################################
package Concatenation;
###############################################################################
sub Rule
{
	    Parse::Nibbler::EatIfSee($_[0],	'\{')
	and Parse::Nibbler::CommaSeparatedList::Rule
		($_[0], \&Signal::Rule, $_[1])
	and Parse::Nibbler::EatIfSee($_[0],	'\}')
	or return 0;

	Parse::Nibbler::Bless $_[1];
	
}

&$reg;

###############################################################################
package Signal;
###############################################################################
sub Rule
{
	   Variable::Rule($_[0], $_[1])
	or Constant::Rule($_[0], $_[1]);
}

###############################################################################
package Variable;
###############################################################################
sub Rule
{
	my $signal = [];
	    SimpleIdentifier::Rule($_[0],$signal->[0])
	and Parse::Nibbler::Optional::Rule
		($_[0], \&BitSelect::Rule, $signal->[1])
	or return 0;

	$_[1] = $signal;
	Parse::Nibbler::Bless $_[1];
}

&$reg;


###############################################################################
package BitSelect;
###############################################################################
sub Rule
{
	my $bit_select = [];
	    Parse::Nibbler::EatIfSee($_[0],	'\[')
	and Parse::Nibbler::Eat($_[0], '(\d+)', $bit_select->[0])
	or return 0;

	if(Parse::Nibbler::EatIfSee($_[0],	'\:'))
		{
		Parse::Nibbler::Eat($_[0], '(\d+)', $bit_select->[1])
		or return 0;
		}

	Parse::Nibbler::EatIfSee($_[0],	'\]')
	or return 0;
	
	$_[1] = $bit_select;
	Parse::Nibbler::Bless $_[1];
}

&$reg;



###############################################################################
package Constant;
###############################################################################
sub Rule
{
	Parse::Nibbler::EatIfSee
		($_[0], '([0-9]+)' , my $width );

	$width = 32 unless defined($width);
	    Parse::Nibbler::Eat($_[0],  "'"  ) 
	and Parse::Nibbler::Eat($_[0],  '([bBhHoO])', my $base  )
	or return 0;

	my $match;
	if($base =~ /b/i)
		{$match = '([10XZxz]+)';}
	elsif($base =~ /d/i)
		{$match = '([0-9XZxz]+)';}
	elsif($base =~ /d/i)
		{$match = '([0-9A-Fa-fXZxz]+)';}

	Parse::Nibbler::Eat($_[0], $match, my $value)
	or return 0;

	$_[1] = [ $width, $base, $value ];

	Parse::Nibbler::Bless $_[1];
}

&$reg;



###############################################################################
package SimpleIdentifier;
###############################################################################
sub Rule
{
	Parse::Nibbler::EatIfSee
		($_[0], '([A-Za-z_][A-Za-z_0-9\$]*)' , $_[1] ) 
	and return 1;

	return Parse::Nibbler::Eat($_[0],  '(\\\\[^\s\n]+)' , $_[1] );
}

&$reg;


###############################################################################
package ComplexIdentifier;
###############################################################################

sub Rule
{

	return 0 unless 
		( 	(Parse::Nibbler::See($_[0], '[A-Za-z_]'))  
		  or	(Parse::Nibbler::See($_[0], qr'\\'))  
		);
	my $identifier;
	$_[0]->local_prefix( my $temp_prefix, '' );
	Parse::Nibbler::EatIfSee($_[0], '\s*');

	my $temp_id;
	while(Parse::Nibbler::EatIfSee
		($_[0],  '([A-Za-z_][A-Za-z_0-9\$]*)' , $temp_id ))
		{
		$identifier .= $temp_id;
		$identifier .= '.' if(Parse::Nibbler::EatIfSee
			($_[0], '\.'));
		}

	if(Parse::Nibbler::EatIfSee
		($_[0],  '(\\[^\s\n]+)[\s\n]' , $temp_id ))
		{
		unless($identifier=~m/\.\Z/)
			{
			$_[0]->report_error('expected "." separator');
			return 0;
			}
		$identifier .= $temp_id;
		}

	unless (defined($identifier))
		{
		$_[0]->report_error('expected identifier');
		return 0;
		}

	if ($identifier =~ m/\.$/)
		{
		$_[0]->report_error('invalid identifier');
		return 0;
		}

	$_[1] = $identifier;
	return 1;
}


&$reg;



###############################################################################
###############################################################################

BEGIN
{
	return;
	no strict;
	return unless $main::DEBUG;

	my @symbols = keys(%VerilogGrammar::);
	print "printing symbols\n";
	foreach my $sym (@symbols)
		{
		next unless($sym=~/[a-z]/);
		print "sym is $sym \n";
		my $code_ref = \&$sym;
		*{$sym} = sub
			{
			print "    >" x scalar(@{$_[0]->{pos}});
			print "called $sym \n";
			my $result = &$code_ref;
			print "    <" x scalar(@{$_[0]->{pos}});
			print $sym;
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


###############################################################################
###############################################################################
###############################################################################

1;
__END__

=head1 NAME

VerilogGrammar - Parsing HUGE gate level verilog files a little bit at a time.

=head1 SYNOPSIS

	use VerilogGrammar;
	my $parser = VerilogGrammar->new('filename.v');
	$parser->design_items;

=head1 DESCRIPTION

This module defines a grammar for parsing simple gate-level verilog netlists.
It uses Parse::Nibbler so that large files can be parsed in the program.
The parser accumulates information on a module by module basis as it
parses the file. To do something with this information, create a new
package which overloads the design_items method and do something with
each module as it is parsed.

This module is intended to be an example module that uses Parse::Nibbler.


=head2 EXPORT

None.


=head1 AUTHOR


# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

contact the author via http://www.greglondon.com


=head1 SEE ALSO

Parse::Nibbler

=cut
