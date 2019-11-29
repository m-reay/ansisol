package ANSISol::Game::Solitaire;
#  Solitaire.pm
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

=head1 ANSISol::Game::Solitaire

Slowly this module will contain ALL of the Solitaire game functions. For now we
will have all of the game rules here

NOTE: Needs to be merged from ANSISol::Game

=cut

# ANSISol Modules
use ANSISol::Deck qw/:consts card_color card_value/;

# Export / Constants
use constant;
use Exporter qw/import/;

# -----------------------------------------------------------------------------
# Constants (export): Deck / Card Area Types
# -----------------------------------------------------------------------------
my %const_types = (
	SOLITAIRE_CRD_PILE   => 1,
	SOLITAIRE_CRD_COLUMN => 2,
	SOLITAIRE_CRD_STACK  => 3,
);

# import constants and export all
constant->import( \%const_types );
our %EXPORT_TAGS = ( consts => [ keys %const_types ] );
our @EXPORT_OK   = ( keys %const_types );

# -----------------------------------------------------------------------------
# Constants (private):
# -----------------------------------------------------------------------------
#use constant {
#	PILE_DEAL_NUM => 3, # default number of cards to deal from pile
#};

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# new( layout, state, %opt, &msg )
# - create a new solitaire game *mainly rules* for now - to be merged...
# -----------------------------------------------------------------------------
sub new {
	my ( $class, $layout, $state, $opt, $msg ) = @_;

	# init self
	my $self = {
		layout => $layout,
		state  => $state,
		option => $opt,
		msg    => $msg ? $msg : sub {},
	};
	
	# bless and return
	bless $self, $class;
	return $self;
}

# -----------------------------------------------------------------------------
# isMoveValidTo( dst_type, dst_enum )
# - checks if it valid to move the current card selection(s) to a destination
# - returns 1 if move is valid, otherwise 0
# -----------------------------------------------------------------------------
sub isMoveValidTo {
	my ( $self, $dst_type, $dst_enum ) = @_;
	my $layout = $self->{layout};
	my $state  = $self->{state};
	my $msg    = $self->{msg};

	# --- Get selected object -------------------------------------------------
	my ( $src_obj, $enum );
	if ( $state->{select_pile} ) { # Select: the "pile"
		$src_obj  = $layout->{pile_up};
	}
	elsif ( $enum = $state->{select_column} ) { # Select: a "column"
		$src_obj  = $layout->{columns}->[ $enum -1 ];
	}
	elsif ( $enum = $state->{select_stack} ) { # Select: a "stack"
		$src_obj  = $layout->{stacks}->[ $enum -1 ];
	}

	# --- Validate selected cards can be moved --------------------------------
	my $src_deck  = $src_obj->{deck_up};
	my $src_cards = $src_deck->get_selected();

	# Validate card(s) moving to a "column"
	if ( $dst_type == $const_types{SOLITAIRE_CRD_COLUMN} ) {
		my $dst_obj  = $layout->{columns}->[ $dst_enum -1 ];
		my $dst_deck = $dst_obj->{deck_up};
		my $dst_card = $dst_deck->get_last_card();
		my $src_card = $src_cards->[0];
		my $src_rank = $src_card->{rank};
		my $src_suit = $src_card->{suit};
		
		# get destination suit (if no card [up or down], only a King is valid)
		my $dst_suit = $dst_deck->get_last_card_suit();
		unless ( $dst_suit ) {
			unless ( $dst_obj->{deck_down}->count() ) {
				return 1 if $src_rank eq 'K';
			}
		}

		# suit colour MUST be opposite
		else {
			if ( card_color( $src_card ) != card_color( $dst_card ) ) {
				# match next value (destination -1)
				&$msg( "Debug: match next value: dst/src: ",
					card_value( $dst_card ), '/', card_value( $src_card ) );
				return 1 if ( card_value( $dst_card ) -1 )
					== card_value( $src_card );
			}
		}
	}

	# Validate a card moving to a "stack"
	elsif ( $dst_type == $const_types{SOLITAIRE_CRD_STACK} ) {
		my $dst_obj  = $layout->{stacks}->[ $dst_enum -1 ];
		my $dst_deck = $dst_obj->{deck_up};
		my $src_suit = $src_deck->get_last_card_suit();
		
		# get destination suit (use source if none)
		my $dst_suit = $dst_deck->get_last_card_suit();
		$dst_suit = $dst_suit ? $dst_suit : $src_suit;

		# match suit
		if ( $src_suit eq $dst_suit ) {
			# match next value in suit
			return 1 if ( $dst_deck->get_last_card_value() +1 )
				== $src_deck->get_last_card_value();
		}
	}

	&$msg( "Not a valid move." );
	return 0;
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# - MODULE END ----------------------------------------------------------------
1;
