package ANSISol::Game;
#  Game.pm
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

# constants
use constant {
	PILE_DEAL_NUM => 3, # default number of cards to deal from pile
};

# ANSISol Modules
use ANSISol::Deck;
use ANSISol::Deck::Cards qw{ text_card };
use ANSISol::Game::Solitaire qw{ :consts };

# ASCII Character Definitions
use RN::Term::Screen::chars qw{ :const kbd_char_match };

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# new( deck, layout, opt )
# - create a new solitaire game
#   - layout = {  # layout objects
#         pile_down => obj,
#         pile_up   => obj,
#         columns   => [],
#         stacks    => [],
#     }
#   - opt = {  # options
#         print_msg     => 
#         no_shuffle    => 0, # default is to shuffle
#         pile_deal_num => 1, # number of cards to deal at one time
#         obj_refresh   => &sub( obj ), # refresh a layout object function
#     }
# -----------------------------------------------------------------------------
sub new {
	my ( $class, $deck, $layout, $opt ) = @_;

	# init options: make sure it's a hash
	$opt = {} unless defined $opt;
	
	# set default options; use dummy functions if none provided
	$opt->{pile_deal_num} = PILE_DEAL_NUM unless $opt->{pile_deal_num};
	$opt->{print_msg}     = sub {} unless $opt->{print_msg};
	$opt->{obj_refresh}   = sub {} unless $opt->{obj_refresh};
	
	# init game 'state'
	my %state = (
		select_pile   => 0, # nothing selected
		select_column => 0,
		select_stack  => 0,
	);

	# init self from options
	my $self = $opt;
	$self->{deck}   = $deck;
	$self->{layout} = $layout;
	$self->{state}  = \%state;
	
	# init game rules - to become the main Solitaire module...
	$self->{game}   = new ANSISol::Game::Solitaire(
		$layout, \%state, {}, $opt->{print_msg} );
	
	# init message
	my $print_msg = $self->{print_msg};
	my $msg       = "New game";
	
	# shuffle the deck
	unless ( $opt->{no_shuffle} ) {
		$deck->shuffle();
		$msg .= " (deck shuffled)";
	}
	else
		{ $msg .= " (no shuffle)" }

	# print message
	&$print_msg( $msg );
	
	# bless and return
	bless $self, $class;
	return $self;
}

# -----------------------------------------------------------------------------
# handle_keyinput( scan_code )
# - handles arrow keys for now
# -----------------------------------------------------------------------------
sub handle_keyinput {
	my ( $self, $scan_code ) = @_;
	my $state     = $self->{state};
	my $layout    = $self->{layout};
	my $o_refresh = $self->{obj_refresh};
	
	# init message
	my $print_msg = $self->{print_msg};
	my $dmsg      = "Debug: handle_keyinput(): ";
	
	# arrow UP
	if ( kbd_char_match( $scan_code, VT2XX_KEY_UP ) ) {
		$dmsg .= "UP: ";
		
		# use a selected column
		if ( my $col_id = $state->{select_column} ) {
			my $col_obj     = $layout->{columns}->[ --$col_id ];
			my $col_deck_up = $col_obj->{deck_up};
			
			# get cards / select next card up
			my $cards = $col_deck_up->get_cards();
			for ( my $i = 0; $i < $col_deck_up->count(); $i++ ) {
				if ( $cards->[ $i ]->{select} && $i > 0 ) {
					$cards->[ $i-1 ]->{select} = 1;
					&$o_refresh( $col_obj );
					last;
				}
			}
		}
	}

	# arrow DOWN
	elsif ( kbd_char_match( $scan_code, VT2XX_KEY_DOWN ) ) {
		$dmsg .= "DOWN: ";
		
		# use a selected column
		if ( my $col_id = $state->{select_column} ) {
			my $col_obj     = $layout->{columns}->[ --$col_id ];
			my $col_deck_up = $col_obj->{deck_up};
			
			# get cards / deselect first selected card
			my $cards = $col_deck_up->get_cards();
			for ( my $i = 0; $i < ( $col_deck_up->count() -1 ); $i++ ) {
				if ( $cards->[ $i ]->{select} ) {
					$cards->[ $i ]->{select} = 0;
					&$o_refresh( $col_obj );
					last;
				}
			}
		}
	}
	
	# Debug message
	&$print_msg( $dmsg );
}

# -----------------------------------------------------------------------------
# deal()
# - deal the cards, unless a game is in progress
# -----------------------------------------------------------------------------
sub deal {
	my ( $self ) = @_;
	my $deck   = $self->{deck};
	my $layout = $self->{layout};
	
	# init message
	my $print_msg = $self->{print_msg};
	my $msg       = "Deal cards:";
	my $err       = 0; # true on deal error
	
	# 1. eight rounds of dealing to columns 'D'own / 'U'p:
	#   - 1st: D, D, D, D, D, D, D
	#   - 2nd: U, D, D, D, D, D, D - round 2 = column 0
	#   - 3rd: U, U, D, D, D, D, D - round 3 = column 1
	#   - etc... until 8th.
	my %dbg_col_cards;
	my %col_done; # records a column index as done on ONE face up card
	for my $round ( 1..8 ) {
		# deal one card to each column: face down then ONE face up
		for ( my $icol = 0; $icol < scalar @{ $layout->{columns} }; $icol++ ) {
		my $column = $layout->{columns}->[ $icol ];

			# skip this column if it if finished (ONE face up card placed)
			next if $col_done{ $icol };

			# place a face up card
			if ( $icol <= ( $round - 2 ) ) {
				$err = 1 unless $deck->move_card_to( $column->{deck_up} );
				$dbg_col_cards{ $icol } .= 'U';
				$col_done{ $icol } = 1;
			}
			
			# place a face down card
			else {
				$err = 1 unless $deck->move_card_to( $column->{deck_down} );
				$dbg_col_cards{ $icol } .= 'D';
			}
		}
	}
	
	# 2. deal the rest into the pickup pile
	$err = 1 unless $deck->move_card_to( $layout->{pile_down}->{deck_down}, '*' );
	
	# debug info
	$msg .= ' '
		. join( ',', map{ "$_:$dbg_col_cards{$_}" } sort keys %dbg_col_cards )
		. ': pile ' . $layout->{pile_down}->{deck_down}->count() . ':';
	
	# message: done
	$msg .= " (move_card_to error(s)):" if $err;
	&$print_msg( $msg, " done" );
	
	# DEBUG: print pile cards
	&$print_msg( "Cards in pile: ", $layout->{pile_down}->{deck_down}->ansi_deck() );
}

# -----------------------------------------------------------------------------
# pile_deal( sub_refresh )
# - deal the next card(s) from the pile
# -----------------------------------------------------------------------------
sub pile_deal {
	my ( $self, $sub_refresh ) = @_;
	my $layout = $self->{layout};
	my $o_refresh = $self->{obj_refresh};
	
	# pile decks and options
	my $deck_down   = $layout->{pile_down}->{deck_down};
	my $deck_up     = $layout->{pile_up}->{deck_up};
	my $deck_up_opt = $layout->{pile_up}->{deck_opt};
	
	# check we have enough cards left to deal / lower pile_deal_num?
	my $ncards = $deck_down->count();
	my $pile_deal_num = ( $ncards < $self->{pile_deal_num} )
		? $ncards : $self->{pile_deal_num};
	
	# reset now_vis_cards
	$deck_up_opt->{now_vis_cards} = $deck_up_opt->{max_vis_cards};

	# lower the visible card number (max_vis_cards)?
	my $now_vis_cards = $deck_up_opt->{now_vis_cards};
	if ( $now_vis_cards && $now_vis_cards > $pile_deal_num ) {
		$now_vis_cards = $deck_up_opt->{now_vis_cards} = $pile_deal_num;
	}

	# deal one or more cards to deck_up
	if ( $ncards ) {
		for ( 1..$pile_deal_num ) {
			$deck_down->move_card_to( $deck_up );
		}
	}
	
	# reset the decks (move cards back to pile_down)
	else {
		$deck_up->move_card_to( $deck_down, $deck_up->count() );
	}
	
	# call refresh
	&$o_refresh( $layout->{pile_down} );
	&$o_refresh( $layout->{pile_up} );
	
	# reset 'now_vis_cards'
	$deck_up_opt->{now_vis_cards} = $now_vis_cards;
}

# -----------------------------------------------------------------------------
# pile_select( )
# -----------------------------------------------------------------------------
sub pile_select {
	my ( $self )  = @_;
	my $state     = $self->{state};
	my $layout    = $self->{layout};
	my $o_refresh = $self->{obj_refresh};
	my $obj       = $layout->{pile_up};
	my $deck      = $obj->{deck_up};

	# message function
	my $print_msg = $self->{print_msg};
	my $dmsg = "DEBUG: pile_select(): ";

	# return if no card to use
	unless ( $deck->count() ) {
		# debug message
		&$print_msg( $dmsg, "no card available!" );
		return 0;
	}
	
	# toggle selection of the top card
	my $card = $deck->get_last_card();
	if ( $card->{select} ) {
		$state->{select_pile} = 0;
		$card->{select} = 0;
		$dmsg .= "unselected the " . text_card( $card );
	}
	else {
		$state->{select_pile} = 1;
		$card->{select} = 1;
		$dmsg .= "selected the " . text_card( $card );
	}
	
	# refresh
	&$o_refresh( $obj );

	# debug message
	&$print_msg( $dmsg );
}

# -----------------------------------------------------------------------------
# column_select( col )
# -----------------------------------------------------------------------------
sub column_select {
	my ( $self, $col ) = @_;
	my $state     = $self->{state};
	my $layout    = $self->{layout};
	my $o_refresh = $self->{obj_refresh};
	my $sol_game  = $self->{game};

	# return if invalid column / target column
	return -1 unless ( $col >= 1 ) && ( $col <= 7 );
	my $obj       = $layout->{columns}->[ $col -1 ];
	my $deck_down = $obj->{deck_down};
	my $deck_up   = $obj->{deck_up};

	# message function
	my $print_msg = $self->{print_msg};
	my $dmsg = "DEBUG: column_select( $col ): ";
	
	# 1. move a card from the pile
	if ( $state->{select_pile} ) {
		my $pile_obj  = $layout->{pile_up};
		my $pile_deck = $pile_obj->{deck_up};
		
		# validate this move
		return -1 unless $sol_game->isMoveValidTo(
			SOLITAIRE_CRD_COLUMN, $col );
		
		# unselect card / move card to column
		my $card = $pile_deck->get_last_card();
		$card->{select} = 0;
		$state->{select_pile} = 0;
		$pile_deck->move_card_to( $deck_up, 1, { last_first => 1 } );
		
		# lower now_vis_cards / reset if less than 1
		$pile_obj->{deck_opt}->{now_vis_cards}--;
		$pile_obj->{deck_opt}->{now_vis_cards}
			= $self->{pile_deal_num}
				if $pile_obj->{deck_opt}->{now_vis_cards} < 1;
		
		# refresh
		&$o_refresh( $pile_obj );
	}
	
	# 2. move card(s) from another column
	elsif ( $state->{select_column} && $state->{select_column} != $col ) {
		my $col_obj  = $layout->{columns}->[ $state->{select_column} -1 ];
		my $col_deck = $col_obj->{deck_up};
		
		# validate this move
		return -1 unless $sol_game->isMoveValidTo(
			SOLITAIRE_CRD_COLUMN, $col );
		
		# unselect state
		$state->{select_column} = 0;
		
		# move cards
		$col_deck->moved_selected_to( $deck_up );
		
		# refresh
		&$o_refresh( $col_obj );
	}
	
	# 3. move a card from a stack
	elsif ( $state->{select_stack} ) {
		my $stack_obj  = $layout->{stacks}->[ $state->{select_stack} -1 ];
		my $stack_deck = $stack_obj->{deck_up};
		
		# validate this move
		return -1 unless $sol_game->isMoveValidTo(
			SOLITAIRE_CRD_COLUMN, $col );
		
		# unselect state / card
		$state->{select_stack} = 0;
		$stack_deck->unselect();
		
		# move card
		$stack_deck->move_card_to( $deck_up, 1, { last_first => 1 } );
		
		# refresh
		&$o_refresh( $stack_obj );
	}
	
	# 4. de/select column
	else {
		
		# if no deck_up cards...
		unless ( $deck_up->count() ) {
			
			# flip a deck-down card over
			if ( $deck_down->count() ) {
				$deck_down->move_card_to( $deck_up, 1, { last_first => 1 } );
				
				# refresh
				&$o_refresh( $obj );
				
				# debug message
				&$print_msg( $dmsg, "flip one!" );
				return 1;
			}
			
			# return if no card to use
			else {
				# debug message
				&$print_msg( $dmsg, "no card available!" );
				return 0;
			}
		}
		
		# toggle selection of the top card
		my $card = $deck_up->get_last_card();
		if ( $card->{select} ) {
			$state->{select_column} = 0;
			$deck_up->unselect();
			$dmsg .= "unselected all";
		}
		else {
			$state->{select_column} = $col;
			$card->{select} = 1;
			$dmsg .= "selected the " . text_card( $card );
		}
	}
	
	# refresh
	&$o_refresh( $obj );
	
	# debug message
	&$print_msg( $dmsg );
}

# -----------------------------------------------------------------------------
# stack_select( stack )
# -----------------------------------------------------------------------------
sub stack_select {
	my ( $self, $stack ) = @_;
	my $state     = $self->{state};
	my $layout    = $self->{layout};
	my $o_refresh = $self->{obj_refresh};
	my $sol_game  = $self->{game};

	# return if invalid stack
	return -1 unless ( $stack >= 1 ) && ( $stack <= 4 );
	my $obj  = $layout->{stacks}->[ $stack -1 ];
	my $deck = $obj->{deck_up};

	# message function
	my $print_msg = $self->{print_msg};
	my $dmsg = "DEBUG: stack_select( $stack ): ";

	# 1. move a card from the pile
	if ( $state->{select_pile} ) {
		my $pile_obj  = $layout->{pile_up};
		my $pile_deck = $pile_obj->{deck_up};
		
		# move one card
		if ( $pile_deck->count_selected() == 1 ) {
			
			# validate this move
			return -1 unless $sol_game->isMoveValidTo(
				SOLITAIRE_CRD_STACK, $stack );
			
			# unselect state / card
			$state->{select_pile} = 0;
			$pile_deck->unselect();
			
			# move card
			$dmsg .= "moving 1 card to stack $stack";
			$pile_deck->move_card_to( $deck, 1, { last_first => 1 } );

			# lower now_vis_cards / reset if less than 1
			$pile_obj->{deck_opt}->{now_vis_cards}--;
			$pile_obj->{deck_opt}->{now_vis_cards}
				= $self->{pile_deal_num}
					if $pile_obj->{deck_opt}->{now_vis_cards} < 1;

			# refresh
			&$o_refresh( $pile_obj );
		}
		
		# more than one selected
		else {
			$dmsg .= "can only move 1 card at a time ("
				. $pile_deck->count_selected() . " selected)";
		}
	}
	
	# 2. move card from a column
	elsif ( $state->{select_column} ) {
		my $col_obj  = $layout->{columns}->[ $state->{select_column} -1 ];
		my $col_deck = $col_obj->{deck_up};
		
		# validate this move
		return -1 unless $sol_game->isMoveValidTo(
			SOLITAIRE_CRD_STACK, $stack );
		
		# move one card
		if ( $col_deck->count_selected() == 1 ) {
			
			# unselect state / card
			$state->{select_column} = 0;
			$col_deck->unselect();
			
			# move card
			$dmsg .= "moving 1 card to stack $stack";
			$col_deck->move_card_to( $deck, 1, { last_first => 1 } );
			
			# refresh
			&$o_refresh( $obj );
			&$o_refresh( $col_obj );
		}
		
		# more than one selected
		else {
			$dmsg .= "can only move 1 card at a time ("
				. $col_deck->count_selected() . " selected)";
		}
	}
	
	# 3. move card from an other stack
	elsif ( $state->{select_stack} ) {
		my $stack_obj  = $layout->{stacks}->[ $state->{select_stack} -1 ];
		my $stack_deck = $stack_obj->{deck_up};
		
		# validate this move
		return -1 unless $sol_game->isMoveValidTo(
			SOLITAIRE_CRD_STACK, $stack );
		
		# unselect state / card
		$state->{select_stack} = 0;
		$stack_deck->unselect();
		
		# move card
		$stack_deck->move_card_to( $deck, 1, { last_first => 1 } );
		
		# refresh
		&$o_refresh( $stack_obj );
	}
	
	# 4. de/select stack
	else {
		# return if no card to use
		unless ( $deck->count() ) {
			# debug message
			&$print_msg( $dmsg, "no card available!" );
			return 0;
		}
		
		# toggle selection of the top card
		my $card = $deck->get_last_card();
		if ( $card->{select} ) {
			$state->{select_stack} = 0;
			$deck->unselect();
			$dmsg .= "unselected all";
		}
		else {
			$state->{select_stack} = $stack;
			$card->{select} = 1;
			$dmsg .= "selected the " . text_card( $card );
		}
	}
	
	# refresh
	&$o_refresh( $obj );

	# debug message
	&$print_msg( $dmsg );
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# - MODULE END ----------------------------------------------------------------
1;
