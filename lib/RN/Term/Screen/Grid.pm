package RN::Term::Screen::Grid;
#  Grid.pm
#  
#  Copyright 2019 Mark Reay <mark@reay.net.au>
#  
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  
#  

# Change log:
# ---------------------------------------------------------------------
# v1.0	: new
# ---------------------------------------------------------------------
use strict;
use warnings;
use Readonly;
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Deepcopy  = 1;

=head1 ...

 ...

=head2 ...
=cut

use Term::ANSIColor;

# ----------------------------------------------------------------------
# Error Codes / Messages
# ----------------------------------------------------------------------
my %ERR_MSG;
use constant ERR_FOOBAR		=> 101;
$ERR_MSG{ &ERR_FOOBAR }		= 'Bad foo bar';

# error handler:
# returns undef on return-from-error
# otherwise, returns 1 (usualy skip error / proceed)
sub _err {
	my ( $parent, $code, $msg ) = @_;
	
	# make sure our error buffer is initialised
	die 'Error buffer is NOT initialised' unless $parent->{errors};
	my $errors = $parent->{errors};
	
	# set the error
	push @$errors, {
		code => $code,
		msg  => "$ERR_MSG{ $code }: $msg",
	};
	
	# how do we return: proceed = 1, bail NOT true
	return $parent->{error_ignore} ? 1 : 0;
}

# ----------------------------------------------------------------------
# Constants / Readonly
# ----------------------------------------------------------------------
use constant {
	# grid types
	GRID_TYPE_BINARY     => 8,
	GRID_TYPE_HEX_NIBBLE => 2,

	# can be summed up as an option value
	GRID_TITLE           => 1,
	GRID_TITLE_X         => 2,
	GRID_TITLE_Y         => 4,
	GRID_TITLE_CELLS_X   => 8,
	GRID_TITLE_CELLS_Y   => 16,
	
	# nameing possitions
	GRID_X_AXIS          => 1,
	GRID_Y_AXIS          => 2,
	
	# colors
	DEFAULT_COLOR_TITLE      => 'white',
	DEFAULT_COLOR_AXIS_TITLE => 'magenta',
	DEFAULT_COLOR_CELL_TITLE => 'cyan',
	DEFAULT_COLOR_CELL       => 'white',
	DEFAULT_BGCOLOR_CELL_SEL => 'on_blue',
};

my @exp_const = ( qw(
	GRID_X_AXIS GRID_Y_AXIS
));

my @exp_const_options = ( qw(
	GRID_TYPE_BINARY GRID_TYPE_HEX_NIBBLE
	GRID_TITLE GRID_TITLE_X GRID_TITLE_Y
	GRID_TITLE_CELLS_X GRID_TITLE_CELLS_Y
));

# export constants to all
use Exporter qw/import/;
our %EXPORT_TAGS = ( all => [ @exp_const, @exp_const_options ] );
our @EXPORT_OK   = ( @exp_const, @exp_const_options );

# ----------------------------------------------------------------------
# Constructor
#
# new( x, y, args, opts )
#  - args {
#      - width   : grid cell width
#      - height  : ...height
#      - spacing : spacing between cells
#    }
#  - opts: integer sum of option values
# ----------------------------------------------------------------------
sub new {
	my ( $class, $x, $y, $args, $opts ) = @_;
	# args:
	my %p = map { $_ => $args->{ $_ } } keys %$args;
	my $self = \%p;
	
	# error logging
	$self->{errors} = [];
	
	# init defaults
	$self->{width}   = 1 unless $self->{width};
	$self->{height}  = 1 unless $self->{height};
	$self->{spacing} = 0 unless $self->{spacing};
	$self->{colors}->{title} = DEFAULT_COLOR_TITLE
		unless $self->{colors}->{title};
	$self->{colors}->{axis_title} = DEFAULT_COLOR_AXIS_TITLE
		unless $self->{colors}->{axis_title};
	$self->{colors}->{cell_title} = DEFAULT_COLOR_CELL_TITLE
		unless $self->{colors}->{cell_title};
	$self->{colors}->{cell} = DEFAULT_COLOR_CELL
		unless $self->{colors}->{cell};
	$self->{colors}->{cell_sel} = DEFAULT_COLOR_CELL
		. ' ' . DEFAULT_BGCOLOR_CELL_SEL
			unless $self->{colors}->{cell_sel};
	
	# init options
	my %options = (
		grid_title			=> $opts & GRID_TITLE ? 1 : 0,
		grid_title_x 		=> $opts & GRID_TITLE_X ? 1 : 0,
		grid_title_y		=> $opts & GRID_TITLE_Y ? 1 : 0,
		grid_title_cells_x	=> $opts & GRID_TITLE_CELLS_X ? 1 : 0,
		grid_title_cells_y	=> $opts & GRID_TITLE_CELLS_Y ? 1 : 0,
	);
	$self->{options} = \%options;
	
	# init select
	$self->{select} = {
		start => 0,
		end   => 0,
	};
	
	# init grid
	$self->{grid} = _grid_init( $x, $y, \%options );

	# bless and return
	bless( $self, $class );
	return $self;
}

# ----------------------------------------------------------------------
# Public "Methods"
# ----------------------------------------------------------------------

#
# select( $x, $y, $len )
#  marks a range as selected (highlighted on print)
sub select {
	my ( $self, $x, $y, $len ) = @_;
	my $select = $self->{select};

	# mark a selection
	$len = 1 unless $len;
	$select->{start} = $x * $y;
	$select->{end}   = $select->{start} + $len;

	return 1;
}

#
# unselect()
#  removes a selection
sub unselect {
	my ( $self, $x, $y, $len ) = @_;
	my $select = $self->{select};

	# remove selection
	$select->{start} = 0;
	$select->{end}   = 0;

	return 1;
}

sub sizex {
	my ( $self ) = @_;
	my $grid = $self->{grid}->{grid};
	return scalar @{$grid->[0]};
}

sub sizey {
	my ( $self ) = @_;
	my $grid = $self->{grid}->{grid};
	return scalar @$grid;
}

# set / get an arrayref of grid data
sub data {
	my ( $self, $data ) = @_;
	my $grid  = $self->{grid}->{grid};
	my $sizex = scalar @{$grid->[0]};
	my $sizey = scalar @$grid;
	
	# test if data is valid
	if ( defined $data ) {
		return unless ref $data eq 'ARRAY';
		
		# clear grid
		_grid_clear( $grid );
		
		# add data
		for ( my $idx = 0; $idx < scalar @$data; $idx++ ) {
			_grid_index_value_set( $grid, $sizex, $sizey, $idx, $data->[$idx] );
		}
	}
	
	# return data
	else {
		my @data;
		
		# pull the data
		foreach my $y ( @$grid ) {
			foreach my $val ( @$y ) {
				push @data, $val;
			}
		}

		return \@data;
	}
}

# set / get a value from a cell
sub value {
	my ( $self, $x, $y, $val ) = @_;
	my $grid = $self->{grid}->{grid};

	# invalid pos?
	return if ( $y >= scalar @$grid ) || ( $x >= scalar @{$grid->[0]} );

	# return value?
	return $grid->[$y]->[$x] unless defined $val;
	
	# set value
	$grid->[$y]->[$x] = $val;
}

sub add_cell_title {
	my ( $self, $axis, @vals ) = @_;

	if ( $axis == GRID_X_AXIS ) {
		# cell titles on?
		return unless $self->{options}->{grid_title_cells_x};
		my $cellx_titles = $self->{grid}->{title}->{cellx};
		
		# populate
		for ( my $i = 0; $i < scalar @$cellx_titles; $i++ ) {
			$cellx_titles->[$i] = shift @vals;
			last unless @vals;
		}
	}
	
	elsif ( $axis == GRID_Y_AXIS ) {
		# cell titles on?
		return unless $self->{options}->{grid_title_cells_y};
		my $celly_titles = $self->{grid}->{title}->{celly};
		
		# populate
		for ( my $i = 0; $i < scalar @$celly_titles; $i++ ) {
			$celly_titles->[$i] = shift @vals;
			last unless @vals;
		}
	}
}

sub add_title {
	my ( $self, $axis, $title ) = @_;
	
	if ( $axis == GRID_X_AXIS ) {
		# cell titles on?
		return unless $self->{options}->{grid_title_x};
		
		# title
		$self->{grid}->{title}->{x} = $title;
	}
	
	elsif ( $axis == GRID_Y_AXIS ) {
		# cell titles on?
		return unless $self->{options}->{grid_title_y};
		
		# title
		$self->{grid}->{title}->{y} = $title;
	}
	
	else {
		# titles on?
		return unless $self->{options}->{grid_title};
		
		# title
		$self->{grid}->{title}->{grid} = $title;
	}
}

sub as_string {
	my ( $self ) = @_;
	my $opt         = $self->{options};
	my $grid        = $self->{grid}->{grid};
	my $sizex       = scalar @{$grid->[0]};
	my $sizey       = scalar @$grid;
	my $titles      = $self->{grid}->{title};
	my $width       = $self->{width};
	my $height      = $self->{height};
	my $spacing     = $self->{spacing};
	my $color_title = $self->{colors}->{title};
	my $color_axis_title = $self->{colors}->{axis_title};
	my $color_cell_title = $self->{colors}->{cell_title};
	my $color_cell       = $self->{colors}->{cell};
	my $color_cell_sel   = $self->{colors}->{cell_sel};
	my $select_start     = $self->{select}->{start};
	my $select_end       = $self->{select}->{end};
	my $idx = 0; # keep track of the index of each cell
	
	# 'Y' cell title width
	my $width_yct = length $titles->{celly}->[0];

	# left spacing for 'Y' title, if any / ytitle offset
	my $space_left = $opt->{grid_title_y} ? ( length $titles->{y} )+1 : 0;
	my $ytitle_off = int( $sizey / 2 ) -1;
	
	# widths
	my $width_grid  = ( $sizex + $opt->{grid_title_cells_y} )
					* ( $width + $spacing ) + ( $width_yct - $width);
	my $width_total = $space_left + $width_grid;

	# assemble the string lines / main title
	my $str = $opt->{grid_title} ? color( $color_title )
		. _str_center( $width_total , $titles->{grid} )
		. color( 'reset' ) . "\n\n" : '';
	
	# cell 'X' axis titles
	if ( $opt->{grid_title_cells_x} ) {
		$str .= ' ' x $space_left;
		$str .= ' ' x ( $width_yct + $spacing ) if $opt->{grid_title_cells_y};
		$str .= color( $color_cell_title );
		$str .= _str_fixed_vals( $width, $titles->{cellx}, $spacing );
		$str .= color( 'reset' ) . "\n";
	}
	
	# assemble the main grid (keep track of x/y coords)
	for ( my $y = 0; $y < $sizey; $y++ ) {
		# 'Y' title
		if ( $opt->{grid_title_y} && $y == $ytitle_off ) {
			$str .= color( $color_axis_title ) . $titles->{y} . ' '
				 . color( 'reset' );
		}
		
		# Y title spacing
		else { $str .= ' ' x $space_left }
		
		# cell Y titles
		$str .= color( $color_cell_title )
			 . _str_fixed( $width_yct, $titles->{celly}->[$y] ) . color( 'reset' )
			 . ' ' x $spacing if $opt->{grid_title_cells_y};
		
		# grid values
		for ( my $x = 0; $x < scalar @{$grid->[$y]}; $x++ ) {
			$idx++; # increment current index
			
			# set colour
			my $color = ( $idx >= $select_start && $idx < $select_end )
				? $color_cell_sel : $color_cell;
			
			# print cell
			$str .= ' ' x $spacing if $x;
			$str .= color( $color )
				. _str_fixed( $width, $grid->[$y]->[$x] ) . color( 'reset' );
		}
		$str .= "\n";
	}
	
	# 'X' title
	$str .= ' ' x $space_left . color( $color_axis_title )
		 . _str_center( $width_grid, $titles->{x} ) . color( 'reset' )
		 . "\n" if $opt->{grid_title_x};

	return $str;
}

# ----------------------------------------------------------------------
# "Private" Subs
# ----------------------------------------------------------------------
# $self->{grid} = _grid_init( $x, $y, \%options );
sub _grid_init {
	my ( $x, $y, $options ) = @_;
	
	# create a 2D array
	my @grid = map{
			[ map{ '' } (1..$x) ]
		} (1..$y);
	
	return {
		grid => \@grid,
		title => {
			x     => '',
			y     => '',
			cellx => [ map{ '' } (1..$x) ],
			celly => [ map{ '' } (1..$y) ],
		},
	};
}

sub _grid_clear {
	my ( $grid, $gopt ) = @_;

	foreach my $y ( @$grid ) {
		foreach my $cell ( @$y ) {
			$cell = '';
		}
	}
}

sub _grid_index_value_set {
	my ( $grid, $sizex, $sizey, $idx, $val ) = @_;
	my $y = int( $idx / $sizex );
	my $x = $idx - ( $y * $sizex );
	
	# set
	$grid->[$y]->[$x] = $val;
}

sub _str_fixed {
	my ( $width, $str ) = @_;
	
	# trim string
	$str = substr( $str, 0, $width ) if length( $str ) > $width;
	
	# pad string
	my $pad = $width - length( $str );
	$str .= ' ' x $pad if $pad;
	
	return $str;
}

sub _str_fixed_vals {
	my ( $width, $vals, $spacing ) = @_;
	my $str = '';
	for ( my $i=0; $i < scalar @$vals; $i++ ) {
		$str .= ' ' x $spacing if $i && $spacing;
		$str .= _str_fixed( $width, $vals->[$i] );
	}
	return $str;
}

sub _str_center {
	my ( $width, $str ) = @_;

	# trim string
	$str = substr( $str, 0, $width ) if length( $str ) > $width;

	# pad string
	my $pad  = int( ($width - length( $str )) / 2 );

	return ' ' x $pad . $str;
}

1;

# vim: shiftwidth=4 tabstops=4 ft=perl
