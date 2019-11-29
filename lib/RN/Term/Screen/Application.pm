package RN::Term::Screen::Application;
#  Application.pm
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

# Terminal
use Term::ANSIScreen qw/:screen/; # for cls call
use Term::ReadKey;

# Screen
use RN::Term::Screen qw/:all/;
use RN::Term::Screen::chars qw{ :const kbd_char_match empty_readkey_buffer };
use RN::Term::Screen::Grid qw/:all/;

# Defaults
Readonly my $SCREEN_TITLE    => 'Default Title';
Readonly my $SCREEN_COLS_MIN => 80;
Readonly my $SCREEN_ROWS_MIN => 25;
Readonly my $APP_EXIT_KEY    => KBD_Q;
Readonly my $CELL_BUFFER_MAX => 100;

# Flags
use constant {
	CELL_TYPE_NONE       => 0, # No special type
	CELL_TYPE_SCROLL_T2B => 1, # Scroll box top-to-bottom
	CELL_TYPE_SCROLL_B2T => 2, # Scroll box bottom-to-top
	CELL_TYPE_FIELDS     => 3, # A group of fields
};

# Export
use Exporter qw/import/;
my @constant_export = ( qw(
	CELL_TYPE_NONE
	CELL_TYPE_SCROLL_T2B
	CELL_TYPE_SCROLL_B2T
	CELL_TYPE_FIELDS
));
our %EXPORT_TAGS = ( const => [ @constant_export ] );
our @EXPORT_OK   = ( @constant_export );

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

# ...

# ----------------------------------------------------------------------
# Constructor
# ----------------------------------------------------------------------
# new( %args, %layout, %opt )
# args:
#  - title    : main screen title
#  - cols-min : terminal columns (minimum)
#  - rows-min : terminal rows (minimum)
# opt:
#  - exit-key : keyboard key to exit Application
# ----------------------------------------------------------------------
sub new {
	my ( $class, $args, $layout, $opt ) = @_;

	# init args / add error log
	$args = {} unless defined $args;
	$args->{errors} = [];

	# args: defaults
	$args->{title}    = $args->{title}    ? $args->{title}: $SCREEN_TITLE;
	$args->{'cols-min'} = $args->{'cols-min'} ? $args->{'cols-min'}: $SCREEN_COLS_MIN;
	$args->{'rows-min'} = $args->{'rows-min'} ? $args->{'rows-min'}: $SCREEN_ROWS_MIN;
	
	# opt: defaults
	$opt = {} unless defined $opt;
	$opt->{'exit-key'}  = $opt->{'exit-key'}  ? $opt->{'exit-key'}: $APP_EXIT_KEY;
	$args->{opt} = $opt;

	# init screen
	my $screen = new RN::Term::Screen( $args->{'cols-min'}, $args->{'rows-min'},
		$args->{title}, { fullscreen => 1 } );

	# init self from args
	my %p = map { $_ => $args->{ $_ } } keys %$args;
	my $self = \%p;
	$self->{screen} = $screen;
	
	# clean up task list (list of subs)
	$self->{cleanup} = [];
	
	# init layout
	$self->{layout} = __init_layout( $screen, $layout );
	$screen->refresh();
	
	# init keymap
	$self->{keymap} = []; # contains a list of hashes (keys: scancode, sub)

	# bless and return
	bless( $self, $class );
	return $self;
}

# ----------------------------------------------------------------------
# Public "Methods"
# ----------------------------------------------------------------------

#
# cell_type( $name, $type )
# - sets or returns a cell type
sub cell_type {
	my ( $self, $name, $type ) = @_;
	my $cell_opt = $self->{layout}->{cell_opt};
	
	# lookup table cell options by name
	my $opt  = $cell_opt->{$name} or return;
	
	# set the type
	if ( $type ) {
		$opt->{type} = $type;
	}
	
	# return type
	return $opt->{type};
}

#
# cell_field( $name, $field, $title )
# - creates a field OR returns it's title
sub cell_field {
	my ( $self, $name, $field, $title ) = @_;
	my $cells    = $self->{layout}->{cells};
	my $cell_opt = $self->{layout}->{cell_opt};
	
	# lookup table cell / options by name
	my $cell = $cells->{$name} or return;
	my $opt  = $cell_opt->{$name} or return;
	
	# return if not CELL_TYPE_FIELDS
	return unless $opt->{type} == CELL_TYPE_FIELDS;
	
	# create fields hash (if needed)
	$cell->{fields} = [] unless ref $cell->{fields} eq 'ARRAY';
	my $fields = $cell->{fields};

	# lookup / create field
	my $f = ( map{ $_->{field} eq $field ? $_ : () } @$fields )[0];
	unless ( $f ) {
		$f = { field => $field, value => '' };
		push @$fields, $f;
	}

	# set the field title
	if ( $title ) {
		
		# update title / buffer
		$f->{title} = $title;
		__cell_buffer_add( $cell, 'flush',
			[ map{ "$_->{title}: $_->{value}" } @$fields ] );
		
		# refresh
		$self->refresh( $name );
		return 1;
	}
	
	# return the field title
	return $f->{title};
}

# cleanup ( $sub )
# add a clean up task
#
sub cleanup {
	my ( $self, $sub ) = @_;
	my $cleanup = $self->{cleanup};
	
	# add sub
	push @$cleanup, $sub;
}

#
# field( $field, $value )
# - sets OR returns a field value
sub field {
	my ( $self, $field, $value ) = @_;

	# search for the field
	my ( $fhash, $cell ) = $self->_find_field( $field )
		or return;

	# set the field value
	if ( $value ) {
		$fhash->{value} = $value;
		
		# refresh buffer
		my $fields = $cell->{fields};
		__cell_buffer_add( $cell, 'flush',
			[ map{ "$_->{title}: $_->{value}" } @$fields ] );

		# refresh
		$self->refresh( $cell->{name} );
		return 1;
	}
	
	# return the field value
	return $fhash->{value};
}

#
# keybind( $scancode, $sub )
#  - connects a keyboard key with a sunction
sub keybind {
	my ( $self, $scancode, $sub ) = @_;	
	my $keymap = $self->{keymap};
	
	# return if scancode exists
	return if $self->_find_mapped_key( $scancode );
	
	# add a new mapping
	push @$keymap, {
			scancode => $scancode,
			sub      => $sub
		};
	
	# return true
	return 1;
}

#
# print( $name, @str )
#  - print text to a named table cell
sub print {
	my ( $self, $name, @str ) = @_;	
	my $cells    = $self->{layout}->{cells};
	my $cell_opt = $self->{layout}->{cell_opt};
	
	# lookup table cell id / cell options by name
	my $cell = $cells->{$name} or return;
	my $cid  = $cell->{id} or return;
	my $opt  = $cell_opt->{$name} or return;

	# handle for cell types
	my $buffer;
	if ( $opt->{type} == CELL_TYPE_SCROLL_T2B ) {
		$buffer = __cell_buffer_add( $cell, 'push', \@str );
	}
	elsif ( $opt->{type} == CELL_TYPE_SCROLL_B2T ) {
		$buffer = __cell_buffer_add( $cell, 'unshift', \@str );
	}
	elsif ( $opt->{type} == CELL_TYPE_NONE ) {
		$buffer = __cell_buffer_add( $cell, 'flush', \@str );
	}
	
	# refresh cell
	$self->refresh( $name );
}

#
# refresh( $name )
#  - refresh screen object(s)
sub refresh {
	my ( $self, $name ) = @_;
	my $screen   = $self->{screen};
	my $cells    = $self->{layout}->{cells};
	my $cell_opt = $self->{layout}->{cell_opt};

	# select cell(s) to refresh
	my @names = $name ? $name : keys %$cells;
	
	# refresh each cell
	foreach $name ( @names ) {

		# lookup table cell / id / options
		my $cell = $cells->{$name} or next;
		my $cid  = $cell->{id} or next;
		my $opt  = $cell_opt->{$name} or next;
		
		# get the buffer / row count - use buffer length if < rows
		my $buffer  = $cell->{buffer};
		my $nbuffer = scalar @$buffer;
		my $rows    = $screen->get_cell_rows( $cid );
		$rows = $nbuffer if $nbuffer < $rows;

		# clear the cell
		$screen->clear_cell( $cid );

		# print the top lines: 0..($rows-1)
		unless ( $opt->{type} == CELL_TYPE_SCROLL_T2B ) {
			my @lines = map{ $buffer->[$_] } (0..($rows-1));
			$screen->print_cell( $cid, { auto_crlf => 1 }, \@lines );
		}
		
		# print the bottom lines: ($nbuffer-$rows)..($nbuffer-1)
		else {
			my @lines = map{ $buffer->[$_] } (($nbuffer-$rows)..($nbuffer-1));
			$screen->print_cell( $cid, { auto_crlf => 1 }, \@lines );
		}
	}
}

#
# running( $$scancode )
#  - returns true while the Application is running
sub running {
	my ( $self, $scancode ) = @_;
	my $screen   = $self->{screen};
	my $exit_key = $self->{opt}->{'exit-key'};
	
	# --- waits for a keystroke for one second ---
	my $key;
	ReadMode 4; # ReadKey: raw mode
	while ( not defined ($key = ReadKey(1)) ) { # wait 1 second

		# if screen size has changed: refresh
		if ( $screen->term_size_rescan() ) {
			$self->refresh();
		}
	}
	
	# get full scan code (empty the buffer)
	my $key_scan = empty_readkey_buffer( $key );
	ReadMode 0; # ReadKey: normal mode

	# Exit Application key pressed
	if ( kbd_char_match( $key_scan, $exit_key ) ) {
		cls;				# clear screen
		$self->_cleanup();	# run clean up tasks
		return 0;			# return false
	}
	
	# Process a custom key mapping
	elsif ( my $map = $self->_find_mapped_key( $key_scan ) ) {
		# mapped callback
		&{$map->{sub}}();
	}
	
	# update scancode
	$$scancode = $key_scan;
	
	# return true (running)
	return 1;
}

# ----------------------------------------------------------------------
# "Private" Methods
# ----------------------------------------------------------------------

# clean up tasks to run on termination
sub _cleanup {
	my ( $self ) = @_;
	my $cleanup = $self->{cleanup};
	
	# run each sub (last first)
	foreach my $sub ( reverse @$cleanup ) {
		&$sub();
	}
}

#
# _find_field( $field )
# - searches for a field by name and returns a hash ref OR undef
# - returns: ( $field_hash, $cell )
sub _find_field {
	my ( $self, $field ) = @_;
	my $cells    = $self->{layout}->{cells};
	my $cell_opt = $self->{layout}->{cell_opt};
	
	# return unless field exists
	return unless $field;
	
	# search through each cell that is of type: CELL_TYPE_FIELDS
	foreach my $cell_name ( keys %$cells ) {
		my $opt  = $cell_opt->{$cell_name};
		
		# select cell if CELL_TYPE_FIELDS
		next unless $opt->{type} == CELL_TYPE_FIELDS;
		my $cell = $cells->{$cell_name};
		
		# find field
		foreach my $field_hash ( @{$cell->{fields}} ) {
			return ( $field_hash, $cell ) if $field_hash->{field} eq $field;
		}
	}
	
	# field not found
	return;
}

#
# _find_mapped_key( $scancode )
#  - returns the keymap entry for $scancode OR false
sub _find_mapped_key {
	my ( $self, $scancode ) = @_;
	my $keymap = $self->{keymap};

	# we just want an array of bytes, strip out of scan HASH
	$scancode = $scancode->{scan}
		if ref $scancode eq 'HASH' && exists $scancode->{scan};

	# lookup scancode
	foreach my $map ( @$keymap ) {
		return $map if kbd_char_match( $scancode, $map->{scancode} );
	}
}

# ----------------------------------------------------------------------
# "Private" Subs
# ----------------------------------------------------------------------

#
# __cell_buffer_add( $cell, $action, \@str )
# - action: 'unshift', 'push', 'flush'
sub __cell_buffer_add {
	my ( $cell, $action, $str ) = @_;
	my $buffer = $cell->{buffer};
	
	# push or unshift lines to buffer / trim to $CELL_BUFFER_MAX length
	if ( $action eq 'push' ) {
		push @$buffer, map{ split /\n/, $_ } @$str;
		splice @$buffer, 0, ( scalar @$buffer - $CELL_BUFFER_MAX )
			if scalar @$buffer > $CELL_BUFFER_MAX; # remove from start
	}
	elsif ( $action eq 'unshift' ) {
		unshift @$buffer, map{ split /\n/, $_ } @$str;
		splice @$buffer, ( $CELL_BUFFER_MAX - scalar @$buffer )
			if scalar @$buffer > $CELL_BUFFER_MAX; # remove from end
	}
	elsif ( $action eq 'flush' ) {
		splice @$buffer, 0, scalar @$buffer; # flush
		push @$buffer, map{ split /\n/, $_ } @$str;
	}

	# return buffer
	return $buffer;
}

sub __init_layout {
	my ( $screen, $layout ) = @_;
	my %cells; # stores Screen table cell references

	# decode: size:name|title - output 1) table 2) cell
	my $__decode_layout_def = sub {
		my ( $code, $output ) = @_;
		my $orient = $code; # init orientation
		
		# add variable size, if none defined
		$orient = "*:$orient" unless $orient =~ m/:/;
		
		# check for and remove '|' decoration flag (capture title)
		my ( $deco, $title );
		if ( $deco = ( $orient =~ s/\|(.*)$// ) ? 1 : 0 ) { $title = $1 }
		
		# get size, split off orient
		( my $size, $orient ) = split /:/, $orient, 2;

		# return cell
		return ( $size, $orient, $title ) if $output == 2;
		
		# return table: use Screen orient / deco flags
		$orient = $orient eq 'HORIZ' ? TABLE_HORIZ : $orient eq 'VERT' ? TABLE_VERT : '';
		$deco   = $deco ? TABLE_DECO_DIVLINES : 0;
		return ( $size, $orient, $deco ); # size, name, title
	};
	
	# create a table: create and process sub-tables
	my $create_table_ref; # stores the ref after definition for internal calls
	my $__create_table = sub {
		my ( $parent, $key, $cells ) = @_;
		
		# decode table parameters
		my ( $size, $orient, $deco ) = &$__decode_layout_def( $key, 1 );

		# process table cells - MUST be an array
		if ( ref $cells eq 'ARRAY' ) {
			
			# stores created table cell info
			my @create_cells; # { name, size, title, table, id }

			# gather info from cells
			foreach my $cell ( @$cells ) {
				
				# normal cell
				unless ( ref $cell ) {
					my ( $_size, $_name, $_title ) = &$__decode_layout_def( $cell, 2 );
					push @create_cells,
						{ size => $_size, name => $_name, title => $_title };
				}
				
				# sub-table
				elsif ( ref $cell eq 'HASH' ) {
					if ( scalar keys %$cell == 1 ) {
						my $k = ( keys %$cell )[0];
						my $_size = ( &$__decode_layout_def( $k, 1 ) )[0];
						push @create_cells,
							{ size => $_size, table => $cell, key => $k };
					}
				}
			}
			
			# create the table / update ids
			my @create_ids = $screen->table_define( $parent,
				[ map{ $_->{size} } @create_cells ], $orient, $deco,
					 [ map{ $_->{title} } @create_cells ] );
			map{ $_->{id} = shift @create_ids } @create_cells;
			
			# update cells hash / create any sub-tables
			foreach my $create_cell ( @create_cells ) {

				# add named cell to cells hash
				unless ( $create_cell->{table} ) {
					
					# add cell buffer / add to cells
					$create_cell->{buffer} = [];
					$cells{ $create_cell->{name} } = $create_cell;
				}
				
				# create a sub-table
				else {
					my $k = $create_cell->{key};			# table key
					my $t = $create_cell->{table}->{$k};	# table hash
					&$create_table_ref( $create_cell->{id}, $k, $t );
				}
			}
		}
	};
	$create_table_ref = $__create_table;

	# process the layout object, must be HASH and contain only 1 key
	if ( ref $layout eq 'HASH' && scalar keys %$layout == 1 ) {
		my $key = ( keys %$layout )[0];
		
		# process table structure
		&$__create_table( 0, $key, $layout->{$key} );
	}
	
	# init cell options
	my %cell_opt = map{ $_ => { type => CELL_TYPE_NONE } } keys %cells;
	
	# return layout table cells and options
	return {
		cells    => \%cells,
		cell_opt => \%cell_opt
	};
}

1;

# vim: shiftwidth=4 tabstops=4 ft=perl
