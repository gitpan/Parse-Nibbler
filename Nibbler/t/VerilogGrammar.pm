package VerilogGrammar;

=for

    VerilogGrammar - Parsing HUGE gate level verilog files a little bit at a time.
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

our @ISA = qw( Parse::Nibbler );

use Data::Dumper;


use Parse::Nibbler;

our $VERSION = '1.08';



#############################################################################
# Lexer
#############################################################################
#############################################################################
sub Lexer
#############################################################################
{
  my $p = $_[0];

  while(1)
    {
      my $line = $p->[Parse::Nibbler::line_number];
      my $col = pos($p->[Parse::Nibbler::current_line]);

      # if at end of line
      if (
	  length($p->[Parse::Nibbler::current_line]) ==
	  pos($p->[Parse::Nibbler::current_line])
	 )
	{
	  $p->[Parse::Nibbler::line_number] ++;
	  # print "line ". $p->[Parse::Nibbler::line_number]."\n";
	  my $fh = $p->[Parse::Nibbler::handle];
	  $p->[Parse::Nibbler::current_line] = <$fh>;

	  unless(defined($p->[Parse::Nibbler::current_line]))
	    {
	      return bless [ '!EOF!', '!EOF!', $line, $col ], 'Lexical';
	    }

	  chomp($p->[Parse::Nibbler::current_line]);
	  pos($p->[Parse::Nibbler::current_line]) = 0;
	  redo;
	}

      # look for leading whitespace and possible comment to end of line
      if($p->[Parse::Nibbler::current_line] =~ /\G\s+(?:\/\/.*)?/gco)
	{
	  redo;
	}


      # look for possible identifiers
      if($p->[Parse::Nibbler::current_line] =~ 
	 /\G(
	       \$?[a-zA-Z_][a-zA-Z0-9_\$]*(?:\.[a-zA-Z_][a-zA-Z0-9_\$]*)*
	     | \$?(?:\\[^\s]+)\s
	    )
	 /gcxo
	)
	{
	  return bless ['Identifier', $1, $line, $col], 'Lexical';
	}


      # look for a 'Number' in Verilog style of number
      #  [unsigned_number] 'd unsigned_number
      #  [unsigned_number] 'o octal_number
      #  [unsigned_number] 'b binary_number
      #  [unsigned_number] 'h hex_number
      #   unsigned_number [ . unsigned_number ] [ e [+-] unsigned_number ]
      if($p->[Parse::Nibbler::current_line] =~ 
	 /\G(
	       (?:\d+)?\'
	          (?:
		     [dD][0-9xXzZ]+
		   | [oO][0-7xXzZ]+
		   | [bB][01xXzZ]+
		   | [hH][0-9a-fA-FxXzZ]
		  )

	     | \d+(?:\.\d+)?(?:e[+-]?\d+)?
	    )
	 /gcxo
	)
	{
	  return bless ['Number', $1, $line, $col ], 'Lexical';
	}

      # else get a single character and return it.
      $p->[Parse::Nibbler::current_line] =~ /\G(.)/gco;
      return bless [$1, $1, $line, $col ], 'Lexical';

    }
}








###############################################################################
Register 
( 'Number', sub 
###############################################################################
  {
    $_[0]->TypeIs('Number');
  }
);

###############################################################################
Register 
( 'Identifier', sub 
###############################################################################
  {
    $_[0]->TypeIs('Identifier');
  }
);


###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################

###############################################################################
Register 
( 'SourceText', sub 
###############################################################################
  {
    $_[0]->Description('{*}');
  }
);

###############################################################################
Register 
( 'Description', sub 
###############################################################################
  {
    $_[0]->ModuleDeclaration;
  }
);


my $module_name;

###############################################################################
Register 
( 'ModuleDeclaration', sub 
###############################################################################
  {
    my $p = $_[0];
    $module_name=undef;
    $p->ValueIs('module');
    $module_name = $p->[Parse::Nibbler::list_of_rules_in_progress]->[1];
    $p->TypeIs('Identifier');
    $p->ListOfPorts  if ($p->PeekValue eq '(');
    $p->ValueIs(';');
    $p->ModuleItem('{*}');
    $p->ValueIs('endmodule');
  },

  sub
  {
    return $module_name;
  }
);

###############################################################################
Register 
( 'ListOfPorts', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('(');
    $p->PortList;
    $p->ValueIs(')');
  }
);

###############################################################################
Register
( 'PortList', sub
###############################################################################
  {
    $_[0]->AlternateRules( 'AnonPortExpressionList', 'NamedPortExpressionList' );
  }
);


###############################################################################
Register 
( 'NamedPortExpressionList', sub 
###############################################################################
  {
    $_[0]->NamedPortExpression('{+}/,/');
  }
);

###############################################################################
Register 
( 'AnonPortExpressionList', sub 
###############################################################################
  {
    $_[0]->AnonPortExpression('{+}/,/');
  }
);


###############################################################################
Register 
( 'NamedPortExpression', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('.');
    $p->TypeIs('Identifier');
    $p->ValueIs('(');
    $p->AnonPortExpression('{?}');
    $p->ValueIs(')');
  }
);


###############################################################################
Register 
( 'AnonPortExpression', sub 
###############################################################################
  {
    my $p = $_[0];
    if ($p->PeekValue eq '{')
      {
	$p->ConcatenatedPortReference;
      }
    else
      {
	$p->PortReference;
      }
  }
);

###############################################################################
Register 
( 'PortReference', sub 
###############################################################################
  {
    my $p = $_[0];
    if ($p->PeekType eq 'Identifier')
      {
	$p->IdentifierWithPossibleBitSpecifier;
      }
    else
      {
	$p->Number;
      }
  }
);


###############################################################################
Register 
( 'IdentifierWithPossibleBitSpecifier', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->TypeIs('Identifier');
    $p->BitSpecifier  if ($p->PeekValue eq '[');
  }
);



###############################################################################
Register 
( 'BitSpecifier', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('[');
    $p->TypeIs('Number');
    $p->ColonNumber  if ($p->PeekValue eq ':');
    $p->ValueIs(']');
  }
);

###############################################################################
Register 
( 'ColonNumber', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs(':');
    $p->TypeIs('Number');
  }
);

###############################################################################
Register 
( 'ConcatenatedPortReference', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('{');
    $p->PortReference('{+}/,/');
    $p->ValueIs('}');
  }
);

###############################################################################
Register 
( 'ModuleItem', sub 
###############################################################################
  {
    my $p = $_[0];
    if ($p->PeekValue =~ /input|output|inout/o)
      {
	$p->DirectionDeclaration;
      }
    else
      {
       $p->ModuleInstantiation;
      };
  }
);


###############################################################################
Register 
( 'DirectionDeclaration', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->AlternateValues('input', 'output', 'inout');
    $p->Range if ($p->PeekValue eq '[');
    $p->PortIdentifier('{+}');
    $p->ValueIs(';');
  }
);


###############################################################################
Register 
( 'PortIdentifier', sub 
###############################################################################
  {
    $_[0]->TypeIs('Identifier');
  }
);

###############################################################################
Register 
( 'Range', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('[');
    $p->TypeIs('Number');
    $p->ValueIs(':');
    $p->TypeIs('Number');
    $p->ValueIs(']');
  }
);


###############################################################################
Register 
( 'ModuleInstantiation', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->TypeIs('Identifier');
    $p->ParameterValueAssignment  if ($p->PeekValue eq '#');
    $p->ModuleInstance('{+}/,/');
    $p->ValueIs(';');
  }
);

###############################################################################
Register 
( 'ParameterValueAssignment', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->ValueIs('#');
    $p->ValueIs('(');
    $p->PortList('{?}');
    $p->ValueIs(')');

  }
);

###############################################################################
Register 
( 'ModuleInstance', sub 
###############################################################################
  {
    my $p = $_[0];
    $p->TypeIs('Identifier');
    $p->ValueIs('(');
    $p->PortList('{?}');
    $p->ValueIs(')');

  }
);






###############################################################################
###############################################################################
###############################################################################

1;
__END__

=head1 NAME

VerilogGrammar - Parsing HUGE gate level verilog files a little bit at a time.

=head1 SYNOPSIS

	use VerilogGrammar;
	my $p = VerilogGrammar->new('filename.v');
	$p->SourceText;

=head1 DESCRIPTION


This module is intended to be an example module that uses Parse::Nibbler.


=head2 EXPORT

None.


=head1 AUTHOR

    VerilogGrammar - Parsing HUGE gate level verilog files a little bit at a time.
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

Parse::Nibbler

=cut
