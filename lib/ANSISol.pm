package ANSISol;
#  ANSISol.pm
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
our $VERSION = '0.1';
our $TITLE   = 'ANSI Solitaire';

# ANSI Terminal Support
use Term::ANSIColor;
use Term::ANSIScreen qw/:cursor :screen/;
use Term::ReadKey;
use Term::Size;

# RN::Term Modules
use RN::Term::Screen qw/:all/;
use RN::Term::Screen::chars qw{ :const kbd_char_match empty_readkey_buffer };

# ANSISol Modules
use ANSISol::Game;
use ANSISol::Deck;
use ANSISol::Deck::Cards qw/:const ansi_card/;

# Constants
use constant {

	# Terminal
	TRM_ROW_MIN => 38,  # minimum terminal size: rows
	TRM_COL_MIN => 102, # columns

	# Layout types (multi-select)
	TYP_LAYOUT_NONE      => 0,
	TYP_LAYOUT_DECK_UP   => 1,
	TYP_LAYOUT_DECK_DOWN => 3,
	TYP_LAYOUT_TEXT      => 5,

	# Layout options
	OPT_TEXT_SCROLL => 1,
	OPT_DECK_VERT   => 2,
	OPT_DECK_HORIZ  => 3,

};

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# new
# - create a new ANSISol playing area
# -----------------------------------------------------------------------------
sub new {
	my ( $class ) = @_;

	# --- init -----------------------------------------------------------------
	my $self = {
		screen => undef,
		game   => undef, # no game yet
		layout => { # all game layout areas, build each with _layout_obj_new
			pile_down => undef, # remainder of deck (pile)
			pile_up   => undef, # dealt from pile
			pile_title=> undef, # title for the piles
			opt_left  => undef,
			column_titles => [],# titles for columns
			columns   => [],    # columns in play
			stacks    => [],    # complete card stacks
			stack_titles  => [],# titles for complete card stacks
			bottom    => undef,
		},
	};
	
	# --- init screen / tables -------------------------------------------------
	my $screen = new RN::Term::Screen( TRM_COL_MIN, TRM_ROW_MIN, $TITLE,
			{ fullscreen => 1 } )
		or return; # error

	# table: top / bottom
	my ( $cell_top, $cell_bottom )
		= $screen->table_define( 0, [ '*', 4 ], TABLE_HORIZ, TABLE_DECO_DIVLINES );

	# table: left / center / right 
	my ( $cell_left, $cell_center, $cell_right )
		= $screen->table_define( $cell_top, [ 20, '*', 12 ], TABLE_VERT, TABLE_DECO_DIVLINES );

	# table: right_1 / right_2
	my ( $cell_right_1, $cell_right_2 )
		= $screen->table_define( $cell_right, [ 9, '*' ], TABLE_VERT );

	# table: center_top / center_bottom
	my ( $cell_center_top, $cell_center_bottom )
		= $screen->table_define( $cell_center, [ 1, '*' ], TABLE_HORIZ );

	# table: piles / options (left)
	my ( $cell_piles, $opt_left )
		= $screen->table_define( $cell_left,
			[ 14, '*' ], TABLE_HORIZ, TABLE_DECO_DIVLINES );
	
	# table: pile_top / pile_up
	my ( $pile_top, $pile_up )
		= $screen->table_define( $cell_piles,
			[ '*', '*' ], TABLE_HORIZ );
	
	# table: pile_down / pile_down_title
	my ( $pile_down, $pile_down_title )
		= $screen->table_define( $pile_top, [ 9, '*' ], TABLE_VERT );

	# table: card column titles
	my @cells_card_col_title
		= $screen->table_define( $cell_center_top,
			[ '*', '*', '*', '*', '*', '*', '*' ], TABLE_VERT );

	# table: card columns
	my @cells_card_col
		= $screen->table_define( $cell_center_bottom,
			[ '*', '*', '*', '*', '*', '*', '*' ], TABLE_VERT );
	
	# table: complete card stacks
	my @cells_card_stack
		= $screen->table_define( $cell_right_1,
			[ '*', '*', '*', '*' ], TABLE_HORIZ );
	
	# table: titles complete card stacks
	my @cells_card_stack_title
		= $screen->table_define( $cell_right_2,
			[ '*', '*', '*', '*' ], TABLE_HORIZ );

	# --- init layout objects --------------------------------------------------
	my $layout = $self->{layout};
	$layout->{pile_title}  = _layout_obj_new( $pile_down_title, TYP_LAYOUT_TEXT );
	$layout->{pile_down}   = _layout_obj_new( $pile_down, TYP_LAYOUT_DECK_DOWN );
	$layout->{pile_up}     = _layout_obj_new( $pile_up,
		TYP_LAYOUT_DECK_UP, OPT_DECK_HORIZ, { max_vis_cards => 3 } );
	$layout->{opt_left}    = _layout_obj_new( $opt_left, TYP_LAYOUT_TEXT );
	foreach my $cell_id ( @cells_card_col_title ) {
		push @{$layout->{column_titles}}, _layout_obj_new( $cell_id,
			TYP_LAYOUT_TEXT );
	}
	foreach my $cell_id ( @cells_card_col ) {
		push @{$layout->{columns}}, _layout_obj_new( $cell_id,
			TYP_LAYOUT_DECK_UP + TYP_LAYOUT_DECK_DOWN, OPT_DECK_VERT );
	}
	foreach my $cell_id ( @cells_card_stack ) {
		push @{$layout->{stacks}}, _layout_obj_new( $cell_id, TYP_LAYOUT_DECK_UP );
	}
	foreach my $cell_id ( @cells_card_stack_title ) {
		push @{$layout->{stack_titles}}, _layout_obj_new( $cell_id, TYP_LAYOUT_TEXT );
	}
	$layout->{bottom} = _layout_obj_new( $cell_bottom, TYP_LAYOUT_TEXT, OPT_TEXT_SCROLL );

	# --- Titles / Text --------------------------------------------------------
	# Pile title
	_game_print_text( $screen, $layout->{pile_title}, "\n\n\n(Space)\n\n\n  (0)" );

	# Column titles
	for ( my $icol = 0; $icol < scalar @{$layout->{column_titles}}; $icol++ ) {
		_game_print_text( $screen, $layout->{column_titles}->[ $icol ],
			"   (", $icol + 1, ")" );
	}
	
	# Stack titles
	for ( my $ista = 0; $ista < scalar @{$layout->{stack_titles}}; $ista++ ) {
		_game_print_text( $screen, $layout->{stack_titles}->[ $ista ],
			"\n\n\n(", chr( ord( 'A' ) + $ista ), ")" );
	}

	# Text in left area
	_game_print_text( $screen, $layout->{opt_left},
		"Q = Quit" );

	# store screen and refresh
	$self->{screen} = $screen;
	$screen->refresh();

	# bless and return object
	bless $self, $class;
	return $self;
}

# -----------------------------------------------------------------------------
# in_game
# - returns true if there is an active game
# -----------------------------------------------------------------------------
sub in_game {
	my ( $self ) = @_;
	
	return 1 if defined $self->{game};
	return;
}

# -----------------------------------------------------------------------------
# game_new
# - starts a new game
# -----------------------------------------------------------------------------
sub game_new {
	my ( $self ) = @_;
	my $screen = $self->{screen};
	my $layout = $self->{layout};

	# return undef, if game already defined
	return if defined $self->{game};
	
	# init: message function
	my $print_msg = sub {
		_game_print_text( $screen, $layout->{bottom}, @_ );
	};

	# init: game and deck
	$self->{game} = new ANSISol::Game(
		new ANSISol::Deck(), $layout, { # options
			print_msg     => $print_msg,
			obj_refresh   => sub {
				_layout_obj_refresh( $screen, $_[0] ) },
			pile_deal_num => 1,
		}
	);
	
	# deal the cards
	$self->{game}->deal();
	
	# refresh all layout objects
	_layout_refresh( $screen, $layout );
	
	return 1;
}

# -----------------------------------------------------------------------------
# game_play
# - main game play runtime loop
# -----------------------------------------------------------------------------
sub game_play {
	my ( $self ) = @_;
	my $screen = $self->{screen};
	my $layout = $self->{layout};
	my $game   = $self->{game};

	# process key inputs
	my $break_exit; # flag to break run-time
	while ( !$break_exit ) {

		# wait for a keystroke
		my $key;
		ReadMode 4; # ReadKey: raw mode
		while ( not defined ( $key = ReadKey(1) ) ) { # 1 second time out
			# check if screen size has changed
			if ( $screen->term_size_rescan() ) {

				# redraw / refresh layout
				_layout_refresh( $screen, $layout );
			}
		}
		
		# empty the buffer (get full scan code)
		my $key_scan = empty_readkey_buffer( $key );
		ReadMode 0; # ReadKey: normal mode

		# Q/q Pressed?
		if ( kbd_char_match( $key_scan, KBD_Q ) ) {
			# clear screen / exit
			cls;
			$break_exit = 1;
		}
		
		# process game keys
		else {

			# SPACE: deal from pile
			if ( $key eq ' ' ) {
				$game->pile_deal();
			}
			
			# 0: select the top pile card
			elsif ( $key eq '0' ) {
				$game->pile_select();
			}
			
			# 1-7: select a column card
			elsif ( ( ord $key >= ord '1' ) && ( ord $key <= ord '7' ) ) {
				$game->column_select( $key );
			}
			
			# A-D: select a (complete) stack
			elsif ( kbd_char_match( $key_scan, KBD_A, KBD_B, KBD_C, KBD_D ) ) {
				my $stack = ord( uc $key ) - ord( 'A' ) + 1;
				$game->stack_select( $stack );
			}
			
			# internally handled keys
			else {
				$game->handle_keyinput( $key_scan );
			}

		}
	}

	return 1;
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

#
# _layout_obj_new( cell_id, layout_type, layout_opt, deck_opt )
#  - layout_type:
#    - TYP_LAYOUT_NONE, TYP_LAYOUT_DECK_UP, TYP_LAYOUT_DECK_DOWN, TYP_LAYOUT_TEXT
#  - layout_opt:
#    - OPT_TEXT_SCROLL, OPT_DECK_VERT, OPT_DECK_HORIZ
#  - deck_opt:
#    - max_vis_cards : maximum number of visible cards (only last ones shown)
#                      default: no limit
#    - now_vis_cards : current maximum number of visible cards
sub _layout_obj_new {
	my ( $cell_id, $layout_type, $layout_opt, $deck_opt ) = @_;

	# init max/now_vis_cards
	$deck_opt->{now_vis_cards} = $deck_opt->{max_vis_cards};

	my %obj = (
		cell_id   => $cell_id,
#		type      => $layout_type, # don't need to store type, it will be obvious
		opt       => $layout_opt ? $layout_opt : 0,
		deck_up   => undef, # face up
		deck_down => undef, # face down
		deck_opt  => $deck_opt ? $deck_opt : {}, # extra deck options
		strings   => [],    # buffer
		is_text   => 0,
	);
	
	# configure type
	if ( my $type = $layout_type ) {

		# text
		if ( $type >= TYP_LAYOUT_TEXT ) {
			$obj{is_text} = 1;
			$type -= TYP_LAYOUT_TEXT;
		}
		
		# deck_down
		if ( $type >= TYP_LAYOUT_DECK_DOWN ) {
			$obj{deck_down} = new ANSISol::Deck( { empty => 1 } );
			$type -= TYP_LAYOUT_DECK_DOWN;
		}
		
		# deck_up
		if ( $type >= TYP_LAYOUT_DECK_UP ) {
			$obj{deck_up} = new ANSISol::Deck( { empty => 1 } );
			$type -= TYP_LAYOUT_DECK_UP;
		}
	}
	
	return \%obj;
}

#
# _layout_obj_refresh( screen, layout_obj )
sub _layout_obj_refresh {
	my ( $screen, $layout_obj ) = @_;
	my $cell_id = $layout_obj->{cell_id};

	# clear cell
	$screen->clear_cell( $cell_id );
	
	# text
	if ( $layout_obj->{is_text} ) {
		
		# print buffer from the top
		my $buffer = $layout_obj->{strings};
		$screen->print_cell( $cell_id, { auto_crlf => 1 }, @$buffer );

	}
	elsif ( defined $layout_obj->{deck_up} || defined $layout_obj->{deck_down} ) {
		
		# extra deck options
		my $deck_opt = $layout_obj->{deck_opt};
		my $ncards_all = 0; # total cards in each deck
		
		# set deck_down card count
		my $ndeck_down = $layout_obj->{deck_down}
			? $layout_obj->{deck_down}->count() : 0;

		# deck down
		if ( defined $layout_obj->{deck_down} ) {
			my $cards  = $layout_obj->{deck_down}->get_cards();
			$ncards_all += ( my $ncards = scalar @$cards );

			# just print one upside down card, if $ncards > 0
			if ( $ncards > 0 ) {
				$screen->print_cell( $cell_id, {}, ansi_card( CRD_FACE_DOWN ) );
			}
			
		}
		
		# deck up (apply 'now_vis_cards' to limit the number of visible cards)
		if ( defined $layout_obj->{deck_up} ) {
			my $cards  = $layout_obj->{deck_up}->get_cards();
			$ncards_all += ( my $ncards = scalar @$cards );
			
			# set 'now_vis_cards' limit (show only last n cards)
			my $now_vis_cards = $deck_opt->{now_vis_cards}
				? $deck_opt->{now_vis_cards} : $ncards;
			
			# Vertical cards (column)
			if ( $ncards > 1 && $layout_obj->{opt} == OPT_DECK_VERT ) {
				my $row_offset = 0; # += CRD_OFFSET_ROWS
				
				# print cards - apply 'now_vis_cards' limit
				my $icard = 0;
				foreach my $card ( @$cards ) {

					# skip card?
					next unless ++$icard > ( $ncards - $now_vis_cards );

					# print card
					$screen->print_cell( $cell_id, { row_offset => $row_offset },
						ansi_card( $card, {
							card_under => ( $icard == 1 ) && $ndeck_down ? 1 : 0
						} ) );
					$row_offset += CRD_OFFSET_ROWS;
				}
			}
			
			# Horizontal cards (row)
			elsif ( $ncards > 1 && $layout_obj->{opt} == OPT_DECK_HORIZ ) {
				my $col_offset = 0; # += CRD_OFFSET_COLS
				
				# print cards - apply 'now_vis_cards' limit
				my $icard = 0;
				foreach my $card ( @$cards ) {
					
					# skip card?
					next unless ++$icard > ( $ncards - $now_vis_cards );
					
					# print card
					$screen->print_cell( $cell_id, { col_offset => $col_offset },
						ansi_card( $card ) );
					$col_offset += CRD_OFFSET_COLS;
				}
			}
			
			# One card ontop of another
			elsif ( $ncards > 0 ) {
				# just print the last card
				my $card = $cards->[ $ncards - 1 ];
				$screen->print_cell( $cell_id, {}, ansi_card( $card, {
					card_under => $ndeck_down ? 1 : 0 } ) );
			}
			
		}
		
		# placeholder for cards
		unless ( $ncards_all > 0 ) {
			$screen->print_cell( $cell_id, {}, ansi_card( {} ) );
		}
	}
}

#
# _layout_refresh( screen, layouts )
# - refresh all layout objects
sub _layout_refresh {
	my ( $screen, $layouts ) = @_;

	# process each layout object
	foreach my $layout ( keys %$layouts ) {
		my $obj = $layouts->{ $layout };
		
		# process sub-objects
		if ( ref $obj eq 'ARRAY' ) {
			foreach my $sub_obj ( @$obj ) {
				_layout_obj_refresh( $screen, $sub_obj );
			}
		}
		else {
			_layout_obj_refresh( $screen, $obj );
		}
	}
}

#
# _game_print_text( screen, layout_obj, strs )
sub _game_print_text {
	my ( $screen, $layout_obj, @strs ) = @_;
	my $str = join("", @strs);
	
	# return, unless is_text
	return unless $layout_obj->{is_text};
	
	# get related cell size
	my ( $cols, $rows ) = $screen->get_cell_size( $layout_obj->{cell_id} );

	# add message message to strings buffer
	my $buffer = $layout_obj->{strings};
	if ( $layout_obj->{opt} == OPT_TEXT_SCROLL ) {
		
		# push new lines
		foreach my $line ( split /\n/, $str ) {
			push @$buffer, $line;
		}
		
		# shift lines until <= $rows
		while ( scalar @$buffer > $rows ) {
			shift @$buffer;
		}
	}
	else {
		
		# push empty lines until == $rows
		while ( scalar @$buffer < $rows ) {
			push @$buffer, "";
		}
		
		# add text to buffer on static lines (top to bottom)
#		my $i = ( $rows - 1 );
		my $i = 0;
		foreach my $line ( split /\n/, $str ) {
			$buffer->[ $i++ ] = $line;
			last if $i >= $rows;
#			$buffer->[ $i-- ] = $line;
#			last if $i <= 0;
		}
	}
	
	# update cell
	_layout_obj_refresh( $screen, $layout_obj );
}


# - MODULE END ----------------------------------------------------------------
1;
