package RN::Term::Screen;
#  Screen.pm
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
use strict;
use warnings;
use constant;
use Exporter qw/import/;

# ANSI Terminal Support
use Term::ANSIScreen qw/:cursor :screen/;
use Text::ANSI::Util qw/ta_detect ta_length ta_wrap/;
use Term::Size;

# ASCII Character Definitions
use RN::Term::Screen::chars qw/:const/;

# Special ASCII Chars UTF-8
binmode STDOUT, ":encoding(utf8)"; # prevents wide character warnings

# Constants
use constant {
	# ancor points
	ANCOR_TL => 1,
	ANCOR_TR => 2,
	ANCOR_BL => 3,
	ANCOR_BR => 4,
	
	# table orientation
	TABLE_HORIZ => 1,
	TABLE_VERT  => 2,
	
	# table decoration
	TABLE_DECO_DIVLINES => 1, # dividing cell lines
};
my @constant_export = ( qw(
	ANCOR_TL ANCOR_TR ANCOR_BL ANCOR_BR
	TABLE_HORIZ TABLE_VERT
	TABLE_DECO_DIVLINES
));

# export constants to all
our %EXPORT_TAGS = ( all => [ @constant_export ] );
our @EXPORT_OK   = ( @constant_export );

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# new( cols, rows, $title, {attrs} )
# - create a new screen area with a minimum size of: cols x rows
# - attrs:
#   - fullscreen => 0 / 1
#   - ancor      => ANCOR_TL / ANCOR_TR / ANCOR_BL / ANCOR_BR
# -----------------------------------------------------------------------------
sub new {
	my ( $class, $cols, $rows, $title, $attrs ) = @_;
	my $self = {
		title      => $title ? $title : '',
		term_cols  => $cols,
		term_rows  => $rows,
		cols_min   => $cols,
		rows_min   => $rows,
		fullscreen => defined $attrs->{fullscreen} ? $attrs->{fullscreen} : 1,
		cells      => [], # defined cell areas
		# Eg.:
		# cells->[0] = {
		#     col_start => 1,
		#     row_start => 1,
		#     cols      => 10,
		#     rows      => 10,
		# }
		tables     => [], # defined tables
		# Eg.:
		# tables->[0] = {
		#     orient  => TABLE_VERT,
		#     sizes   => ['*', 10],
		#     cells   => [1, 2], # created cell ids
		#     deco    => TABLE_DECO_DIVLINES,
		#     parent_cell => 0 # main screen. Int > 0 is a defined area
		# }
	};
	
	# init: cell 0 (screen area)
	push @{$self->{cells}}, {};
	
	# check terminal size
	return unless ( $self->{term_cols}, $self->{term_rows} )
		= _check_terminal_size( $cols, $rows );
	
	# draw screen
	_screen_redraw( $self );
	
	# bless and return
	bless $self, $class;
	return $self;
}

# -----------------------------------------------------------------------------
# term_size_rescan( )
# - checks if the terminal size has changed and updates settings
# - returns 1 if size has changed
# -----------------------------------------------------------------------------
sub term_size_rescan {
	my ( $self ) = @_;
	my $been_too_small;

	# loop until we have a valid size
	while ( 1 ) {
		# check / get size
		if ( my ( $now_cols, $now_rows )
			= _check_terminal_size( $self->{cols_min}, $self->{rows_min} ) ) {
			
			# has size changed?
			if ( ( $now_cols != $self->{term_cols} )
					|| ( $now_rows != $self->{term_rows} )
					|| ( $been_too_small ) ) {
				# update terminal size and return TRUE
				( $self->{term_cols}, $self->{term_rows} ) = ( $now_cols, $now_rows );
				
				# re-draw screen (recalculate cells)
				_screen_redraw( $self, { recalculate => 1 } );
				return 1;
			}
			
			# size is the same
			return 0;
		}
		
		# terminal size is too small!
		else {
			$been_too_small = 1;
			print "Resize terminal and press ENTER\n";
			my $continue = <STDIN>;
		}
	}
}

# -----------------------------------------------------------------------------
# refresh( )
# - re-draw the screen
# -----------------------------------------------------------------------------
sub refresh {
	my ( $self ) = @_;
	
	_screen_redraw( $self );
}

# -----------------------------------------------------------------------------
# table_define( parent_cell, [sizes], orient, deco, [titles] )
# - create new virtual areas for printing in
#   - orient: orientation: TABLE_HORIZ, TABLE_VERT
#   - sizes:  arrayref of cell sizes. '*' = dynamic
#   - deco:   decoration flags: TABLE_DECO_DIVLINES
#   - titles: arrayref of cell titles
# - return: area index(es)
# -----------------------------------------------------------------------------
sub table_define {
	my ( $self, $parent_cell, $sizes, $orient, $deco, $titles ) = @_;

	# init $titles
	$titles = [] unless $titles;

	# parent is screen, vertical, no decoration (default)
	$parent_cell = 0 unless $parent_cell;
	$orient      = TABLE_VERT unless $orient;
	$deco        = 0 unless $deco;

	# define table
	my %table = (
		orient      => $orient,
		sizes       => $sizes,
		titles		=> $titles,
		cells       => [], # created cell ids
		deco        => $deco,
		parent_cell => $parent_cell,
	);
	
	# creates cells from table definition / calculate cells
	my @cell_idxs = _table_cells_init( $self, \%table );
	_table_recalculate_cells( $self, \%table );
	
	# add table to master tables array
	push @{$self->{tables}}, \%table;

	# return cell indexes
	return @cell_idxs;
}

# -----------------------------------------------------------------------------
# print_cell( cell_idx, {attr}, @strings )
# - prints in a virtual area
# - attr:
#   - col_offset: 0 default
#   - row_offset: 0 default
#   - auto_crlf: 0
# -----------------------------------------------------------------------------
sub print_cell {
	my ( $self, $cell_idx, $attr, @strings ) = @_;
	my $cells = $self->{cells};

	# detect string ref OR use a reference to @string
	my $strings = ref $strings[0] eq 'ARRAY' ? $strings[0] : \@strings;

	# select cell or return
	return unless defined $cell_idx && defined $cells->[ $cell_idx ];
	my $cell = $cells->[ $cell_idx ];
	
	# attributes
	my $col_offset = $attr->{col_offset} ? $attr->{col_offset} : 0;
	my $row_offset = $attr->{row_offset} ? $attr->{row_offset} : 0;
	my $auto_crlf  = $attr->{auto_crlf}  ? $attr->{auto_crlf}  : 0;

	# apply offsets / goto starting position
	my $col_start = $cell->{col_start} + $col_offset;
	my $row_start = $cell->{row_start} + $row_offset;
	my $cols      = $cell->{cols} - $col_offset;
	my $rows      = $cell->{rows} - $row_offset;
	locate( $row_start, $col_start );

	# join strings and process each line
	# Special functions for ANSI encoded text
	# - ta_detect("\e[31mred") => true
	# - ta_length($text) => INT
	# - ta_wrap($text, $width, \%opts) => STR
	my $row = 1;
	my $join_ch = $auto_crlf ? "\n" : "";
	foreach my $line ( split /\n/, join( $join_ch, @$strings ) ) {
		
		# detect ANSI text
		my $is_ansi = ta_detect( $line );
		
		# truncate each line to max length
		if ( $is_ansi && ta_length( $line ) > $cols ) {
			# ANSI text
			$line = split /\n/, ta_wrap( $line, $cols ), 1;
		}
		elsif ( !$is_ansi && length( $line ) > $cols ) {
			# normal text
			$line = substr( $line, 0, $cols );
		}
		
		# print line, move cursor to next staring column
		print "$line\n";
		right( $col_start - 1 );
		
		# last row (end of cell)?
		last if $row++ >= $rows;
	}
}

# -----------------------------------------------------------------------------
# clear_cell( cell_idx  )
# - clears / blanks the cell
# -----------------------------------------------------------------------------
sub clear_cell {
	my ( $self, $cell_idx ) = @_;
	my $cells = $self->{cells};
	
	# select cell or return
	return unless defined $cell_idx && defined $cells->[ $cell_idx ];
	my $cell = $cells->[ $cell_idx ];

	# fill area with spaces
	locate( $cell->{row_start}, $cell->{col_start} );
	foreach ( 1..$cell->{rows} ) {
		print " " x $cell->{cols}, "\n";
		right( $cell->{col_start} - 1 );
	}
}

# -----------------------------------------------------------------------------
# get_cell_size( cell_idx  )
# - returns the cell's size ( cols, rows )
# -----------------------------------------------------------------------------
sub get_cell_size {
	my ( $self, $cell_idx ) = @_;
	my $cells = $self->{cells};
	
	# select cell or return
	return unless defined $cell_idx && defined $cells->[ $cell_idx ];
	my $cell = $cells->[ $cell_idx ];

	return ( $cell->{cols}, $cell->{rows} );
}

# -----------------------------------------------------------------------------
# get_cell_rows( cell_idx  )
# - returns the number of rows in a cell
# -----------------------------------------------------------------------------
sub get_cell_rows {
	my ( $self, $cell_idx ) = @_;
	my $cells = $self->{cells};
	
	# select cell or return
	return unless defined $cell_idx && defined $cells->[ $cell_idx ];
	my $cell = $cells->[ $cell_idx ];

	return $cell->{rows};
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

#
# _check_terminal_size( $rows, $cols )
sub _check_terminal_size {
	my ( $cols, $rows ) = @_;
	
	my ( $term_cols, $term_rows ) = Term::Size::chars *STDOUT{IO};
	if (( $term_cols < $cols ) || ( $term_rows < $rows )) {
		cls();
		print "\nTerminal size must be at least $cols columns by $rows rows.\n";
		print "Your terminal is set to: $term_cols x $term_rows\n";
		return;
	}
	return ( $term_cols, $term_rows );
}

#
# _draw_box( $cols, $rows, $title, {attrs} )
# - attrs:
#   - ch_horiz, ch_vert, ch_tl, ch_tr, ch_bl, ch_br
sub _draw_box {
	my ( $cols, $rows, $title, $attrs ) = @_;
	
	# init $title, %attrs
	$title = '' unless $title;
	$attrs = {} unless $attrs;
	
	# default: single line, sharp corners
	$attrs->{ch_horiz} = ASC_1LN_HRZ unless $attrs->{ch_horiz};
	$attrs->{ch_vert}  = ASC_1LN_VRT unless $attrs->{ch_vert};
	$attrs->{ch_tl}    = ASC_1LN_CTL unless $attrs->{ch_tl};
	$attrs->{ch_tr}    = ASC_1LN_CTR unless $attrs->{ch_tr};
	$attrs->{ch_bl}    = ASC_1LN_CBL unless $attrs->{ch_bl};
	$attrs->{ch_br}    = ASC_1LN_CBR unless $attrs->{ch_br};
	
	# draw the box
#	cls;
	print locate( 1, 1 ),
		chr( $attrs->{ch_tl} ),
		chr( $attrs->{ch_horiz} ) x ( $cols - 2 ),
		chr( $attrs->{ch_tr} ), "\n";
	for ( 1..( $rows - 2 ) ) {
		print chr( $attrs->{ch_vert} ), right( $cols - 1 ), chr( $attrs->{ch_vert} ), "\n";
	}
	print chr( $attrs->{ch_bl} ),
		chr( $attrs->{ch_horiz} ) x ( $cols - 2 ), chr( $attrs->{ch_br} );

	# print title
	print locate( 1, 3 ), " $title \n";
}

#
# _draw_line( col_start, row_start, len, orient, {attr} )
# - attrs:
#   - ch_horiz, ch_vert, title
sub _draw_line {
	my ( $col_start, $row_start, $len, $orient, $attr ) = @_;
	$orient = TABLE_VERT unless $orient;
	
	# default: single line
	$attr->{ch_horiz} = ASC_1LN_HRZ unless $attr->{ch_horiz};
	$attr->{ch_vert}  = ASC_1LN_VRT unless $attr->{ch_vert};
	
	# draw the line
	if ( $orient == TABLE_HORIZ ) {
		locate( $row_start, $col_start );
		print chr( $attr->{ch_horiz} ) x $len, "\n";
		
		# add a title
		if ( my $title = $attr->{title} ) {
			my $tlen_max = $len - 4;
			$title = substr( $title, 0, $tlen_max - 3 ) . '...'
				if length $title > $tlen_max;
			
			# print title
			locate( $row_start, $col_start +1 );
			print " $title \n";
		}
	}
	else { # TABLE_VERT
		for ( 1..$len ) {
			locate( $row_start++, $col_start );
			print chr( $attr->{ch_vert} ), "\n";
		}
	}
}

#
# _table_cells_init( self, table  )
#  - creates cells from table definitions
sub _table_cells_init {
	my ( $self, $table ) = @_;

	# define empty cells from required table sizes
	my @cell_idxs;
	foreach ( @{ $table->{sizes} } ) {

		# new cell object
		my %cell = (
			col_start => undef,
			row_start => undef,
			cols      => undef,
			rows      => undef,
			title     => shift @{ $table->{titles} },
		);

		# get next cell id and add cell to table / master cells
		my $cell_id = scalar @{$self->{cells}};
		push @{$table->{cells}}, $cell_id;
		push @cell_idxs, $cell_id;
		push @{$self->{cells}}, \%cell;
	}
	
	# return new cell ids
	return @cell_idxs;
}

#
# _table_recalculate_cells( self, table_ref )
#  - recalculates all cell sizes based on tables and teminal size
#  - table: optional ( target a specific table)
sub _table_recalculate_cells {
	my ( $self, $table_ref ) = @_;
	
	# loop through all tables
	my $tables = $table_ref ? [ $table_ref ] : $self->{tables};
	foreach my $table ( @$tables ) {
	
		# get parent cell area
		my $parent = $self->{cells}->[ $table->{parent_cell} ];
		my ( $cols, $rows ) = ( $parent->{cols}, $parent->{rows} );
		
		# find the total fixed size / get dynamic count
		my $sizes      = $table->{sizes}; # master size array / template
		my $size_fixed = 0;
		my $ndynamic   = 0;
		my $ncells     = 0;
		foreach my $size ( @$sizes ) {
			if ( $size eq '*' )
				{ $ndynamic++ }
			else
				{ $size_fixed += $size }
			$ncells++;
		}
		
		# find the dynamic size(s) (horizontal OR vertical)
		my $orient       = $table->{orient}; # table orientation
		my $deco         = $table->{deco};   # table decoration
		my $size_total   = ( $orient == TABLE_HORIZ ) ? $rows : $cols;
		$size_total     -= ( $ncells - 1) if $ncells && $deco; # remove total deco lines, if any
		my $size_dynamic = $size_total - $size_fixed;
		my $size_dyn_lo  = int( $size_dynamic / $ndynamic ); # compensate for a non integer
		my $size_dyn_hi  = ( $size_dynamic % $ndynamic )
			? $size_dynamic - ( $size_dyn_lo * ( $ndynamic - 1 ) ) : $size_dyn_lo;
		$size_dynamic    = $size_dyn_lo; # the LAST dynamic cell will be 'hi'
		
		# find last dynamic cell index
		my $dyn_last_idx = -1;
		$ncells          = 0;
		foreach ( @$sizes ) {
			$dyn_last_idx = $ncells if $_ eq '*';
			$ncells++;
		}
		
		# re-define cell sizes
		my $col_pos = $parent->{col_start};
		my $row_pos = $parent->{row_start};
		$ncells     = 0;
		foreach my $size ( @$sizes ) {
			
			# get cell: is dynamic?
			my $cell   = $table->{cells}->[ $ncells ]; # get cell id
			$cell      = $self->{cells}->[ $cell ];    # get the actual cell
			my $is_dyn = $size eq '*' ? 1 : 0;
			
			# add 1 to col / row if decoration is on
			$cell->{col_start} = ( $deco && $orient == TABLE_VERT && $ncells )
				? ++$col_pos : $col_pos;
			$cell->{row_start} = ( $deco && $orient == TABLE_HORIZ && $ncells )
				? ++$row_pos : $row_pos;
			
			# Horizontal (fixed colums)
			if ( $orient == TABLE_HORIZ ) {
				$cell->{cols} = $cols;
				$cell->{rows} = $is_dyn ? $size_dynamic : $size;
				$row_pos     += $cell->{rows};
			}
			
			# Vertical (fixed rows)
			else {
				$cell->{cols} = $is_dyn ? $size_dynamic : $size;
				$cell->{rows} = $rows;
				$col_pos     += $cell->{cols};
			}
			
			# start using 'hi' size if the next cell is the LAST dynamic
			$ncells++;
			$size_dynamic = $size_dyn_hi if $ncells == $dyn_last_idx;
		}
	}
}

#
# _screen_redraw( $self, {attr} )
sub _screen_redraw {
	my ( $self, $attr ) = @_;
	$attr = {} unless defined $attr; # add attr hash

	# clear screen
	cls();
	
	# draw main screen box and title
	_draw_box( $self->{term_cols}, $self->{term_rows}, $self->{title} );
	
	# calculate cell 0 (screen) area:
	my $cell_0 = $self->{cells}->[0];
	$cell_0->{col_start} = 2;
	$cell_0->{row_start} = 2;
	$cell_0->{cols} = $self->{term_cols} - 2;
	$cell_0->{rows} = $self->{term_rows} - 2;
	
	# calculate tables and cells
	_table_recalculate_cells( $self ) if $attr->{recalculate};
	
	# draw table decorations
	foreach my $table ( @{$self->{tables}} ) {
		my $ncells = 0;
		foreach my $cell_idx ( @{$table->{cells}} ) {
			my $cell = $self->{cells}->[ $cell_idx ];
			
			# add decoration to cell?
			if ( $table->{deco} && $ncells ) {
				if ( $table->{orient} == TABLE_HORIZ ) {
					# draw a horizontal line
					_draw_line( $cell->{col_start}, $cell->{row_start} - 1, $cell->{cols},
						TABLE_HORIZ, { title => $cell->{title} } );
				}
				else {
					# draw a vertical line
					_draw_line( $cell->{col_start} - 1, $cell->{row_start}, $cell->{rows},
						TABLE_VERT );
				}
			}
			
			$ncells++;
		}
	}
}

# - MODULE END ----------------------------------------------------------------
1;

# vim: shiftwidth=4 tabstops=4 ft=perl
