package VerilogGrammar;

# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

## See POD after __END__


require 5.005_62;

use strict;
use warnings;

our @ISA = qw( Parse::Nibbler );

use Data::Dumper;


use Parse::Nibbler;

our $VERSION = '1.07';




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

      # delete any leading whitespace and check it again
      if($p->[Parse::Nibbler::current_line] =~ /\G\s+/gc)
	{
	  redo;
	}

      # look for comment to end of line
      if($p->[Parse::Nibbler::current_line] =~ /\G\/\/.*/gc)
	{
	  redo;
	}

      # look for identifier (hierarchical)
      my $identifier = '';
      if( $p->[Parse::Nibbler::current_line] =~ /\G\$/gc )
	{
	  $identifier = "\$";   # system task name
	}

      while(1)
	{
	  if ( $p->[Parse::Nibbler::current_line] =~ /\G([a-zA-Z_][a-zA-Z0-9_\$]*)/gc )
	    {$identifier .= $1;}

	  elsif($p->[Parse::Nibbler::current_line] =~ /\G(\\[^\s]+)\s/gc) 
	    {
	      $identifier .= $1;
	      pos($p->[Parse::Nibbler::current_line]) = pos($p->[Parse::Nibbler::current_line]) - 1; 
	    }

	  # no match and no accumulated identifier string
	  elsif (length($identifier) == 0)
	    { last; } 

	  $p->report_error("bad identifier") if ($identifier =~ /\.$/);

	  if ($p->[Parse::Nibbler::current_line] =~ /\G\./gc)
	    {
	      $identifier .= '.';
	      redo;
	    }

	  if ($identifier =~ /\A\$/)
	    {
	      if(length($identifier) == 1)
		{
		  return bless  ['$', '$', $line, $col ], 'Lexical';
		}
	      else
		{
		  return bless 
		    ['system_task_name', $identifier, $line, $col ], 'Lexical';
		}

	    }

	  else
	    {
	      return bless ['Identifier', $identifier, $line, $col ], 'Lexical';
	    }

	}

      # look for a 'Number' in Verilog style of number
      # [+-] unsigned_number 
      # [+-] [unsigned_number] 'd unsigned_number
      # [+-] [unsigned_number] 'o octal_number
      # [+-] [unsigned_number] 'b binary_number
      # [+-] [unsigned_number] 'h hex_number
      # [+-] unsigned_number . unsigned_number
      # [+-] unsigned_number [ . unsigned_number ] e [+-] unsigned_number

      # first character must be a number or a '
      my $number = '';

      # will ignore optional sign at beginning of number for now.
      # will hope that parser can handle it in rules.

      if ($p->[Parse::Nibbler::current_line] =~ /\G([0-9][0-9_]*)/gc)
	{
	  $number .= $1;
	}

      if ( $p->[Parse::Nibbler::current_line] =~ /\G(\'[dDoObBhH])/gc )
	{
	  $number .= $1;
	  $number = lc($number);

	  # if no number was given to indicate size, default is 32
	  unless($number =~ /\A[0-9]/)
	    {
	      $number = '32' . $number;
	    }

	  if($number=~/d$/)
	    {
	      $p->[Parse::Nibbler::current_line] =~ /\G([0-9][0-9_]*)/gc;
	      unless(defined($1))
		{
		  $p->report_error("Lex error: invalid decimal number") 
		}
	      $number .= $1;
	    }
	  elsif($number=~/o$/)
	    {
	      $p->[Parse::Nibbler::current_line] =~ /\G([xXzZ0-7][xXzZ0-7_]*)/gc;
	      unless(defined($1))
		{
		  $p->report_error("Lex error: invalid octal number") 
		}
	      $number .= $1;
	    }
	  elsif($number=~/b$/)
	    {
	      $p->[Parse::Nibbler::current_line] =~ /\G([xXzZ01][xXzZ01_]*)/gc;
	      unless(defined($1))
		{
		  $p->report_error("Lex error: invalid binary number") 
		}	      $number .= $1;
	    }

	  elsif($number=~/h$/)
	    {
	      $p->[Parse::Nibbler::current_line] =~ /\G([xXzZ0-9a-fA-F][xXzZ0-9a-fA-F_]*)/gc;
	      unless(defined($1))
		{
		  $p->report_error("Lex error: invalid hexadecimal number") 
		}	      $number .= $1;
	    }
	  
	  if($number =~ /_$/)
	    {
	      report_error("Lex: number ended with '_'");
	    }

	  $number = lc($number);
	  $number =~ s/_//g;
	  $number =~ s/\s//g;
	  return bless ['Number', $number, $line, $col ], 'Lexical';
	}
      else  # not a based number ('h), is it a float with exponent
	{
	  if( $p->[Parse::Nibbler::current_line] =~ /\G(\.[0-9][0-9_]*)/gc )
	    {
	      $number .= $1;
	    }

	  if( $p->[Parse::Nibbler::current_line] =~ /\G(\s*[eE]\s*[+-]*\s*[0-9][0-9_]*)/gc )
	    {
	      $number .= $1;
	    }

	  if(length($number)>0)
	    {
	      $number = lc($number);
	      $number =~ s/\s//g;
	      $number =~ s/_//g;
	      return bless ['Number', $number, $line, $col ], 'Lexical';
	    }
	  }

      # else get a single character and return it.
      $p->[Parse::Nibbler::current_line] =~ /\G(.)/gc;
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
    if ($p->PeekValue =~ /input|output|inout/)
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


# Copyright (c) 2001 Greg London. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

contact the author via http://www.greglondon.com


=head1 SEE ALSO

Parse::Nibbler

=cut
