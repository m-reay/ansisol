package ANSISol::Deck;
#  Deck.pm
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
use Exporter qw/import/;

# ANSI Terminal Support
use Term::ANSIColor;

# ASCII Character Definitions
use RN::Term::Screen::chars qw/:const/;

# Constants: shuffle settings
use constant {
	SFL_CUT_OFFSET_PERC => 10, # aim to cut the deck in half, +/- OFFSET PERCentage
	SFL_RIFFLE_PEAL_MAX => 4, # four cards max at a time to interleave
	SFL_OVRHND_PEAL_MIN => 2, # overhand shuffle min - max at a time
	SFL_OVRHND_PEAL_MAX => 12,
	SFL_RIFFLE_TOTAL    => 8,
	SFL_OVRHND_TOTAL    => 4,
	
	# Exported
	DECK_CARD_BLACK => 1,
	DECK_CARD_RED   => 2,
};

# Exports
our %EXPORT_TAGS = ( consts => [ qw{ DECK_CARD_BLACK DECK_CARD_RED } ] );
our @EXPORT_OK   = qw{ DECK_CARD_BLACK DECK_CARD_RED card_color card_value };

# suit symbols and colors
my %CRD_SUIT = (
	'H' => { name => 'Hearts',   symbol => ASC_HRT_SOL, color => 'bright_red',
		value => 1 },
	'C' => { name => 'Clubs',    symbol => ASC_CLB_OUT, color => 'bright_white',
		value => 2 },
	'D' => { name => 'Diamonds', symbol => ASC_DMD_SOL, color => 'bright_red',
		value => 3, reverse => 1 }, # new deck order, sort ranks in reverse
	'S' => { name => 'Spades',   symbol => ASC_SPD_OUT, color => 'bright_white',
		value => 4, reverse => 2 },
); # suit symbols (by value)
my %CRD_SUIT_BYVALUE = map { $CRD_SUIT{ $_ }->{value} => $_ } keys %CRD_SUIT;

# ranks and names (by symbol)
my %CRD_RANK = (
	'A' => { name => 'Ace',   value => 1 },
	'2' => { name => 'Two',   value => 2 },
	'3' => { name => 'Three', value => 3 },
	'4' => { name => 'Four',  value => 4 },
	'5' => { name => 'Five',  value => 5 },
	'6' => { name => 'Six',   value => 6 },
	'7' => { name => 'Seven', value => 7 },
	'8' => { name => 'Eight', value => 8 },
	'9' => { name => 'Nine',  value => 9 },
	'10'=> { name => 'Ten',   value => 10 },
	'J' => { name => 'Jack',  value => 11 },
	'Q' => { name => 'Queen', value => 12 },
	'K' => { name => 'King',  value => 13 },
); # rank symbols (by value)
my %CRD_RANK_BYVALUE = map { $CRD_RANK{ $_ }->{value} => $_ } keys %CRD_RANK;

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# new( {attr} )
# - create a new deck of cards
# - attr:
#   - empty: if set a deck with no cards is returned
# -----------------------------------------------------------------------------
sub new {
	my ( $class, $attr ) = @_;

	my $self = {
		deck => $attr->{empty} ? [] : _deck_create(),
	};
	
	# bless and return
	bless $self, $class;
	return $self;
}

# -----------------------------------------------------------------------------
# shuffle
# - performs a thorough shuffle on the deck, consisting of:
#   - a random number of overhand and riffle shuffles
# Quote: https://www.math.hmc.edu/funfacts/ffiles/20002.4-6.shtml
#   In 1992, Bayer and Diaconis showed that after seven random riffle shuffles
#   of a deck of 52 cards, every configuration is nearly equally likely.
#   Shuffling more than this does not significantly increase the "randomness";
#   shuffle less than this and the deck is "far" from random.
# -----------------------------------------------------------------------------
sub shuffle {
	my ( $self ) = @_;
	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# our shuffle formula, using settings: SFL_RIFFLE_TOTAL & SFL_OVRHND_TOTAL
	# 1. setup a series of shuffles. Randomly selecting riffle or overhand
	#    until the totals of each are reached.
	# 2. cut the deck
	
	# perform a random series of shuffle types
	my %shuffle_types = (
		r => SFL_RIFFLE_TOTAL,
		o => SFL_OVRHND_TOTAL,
	);
	while ( my $n = scalar keys %shuffle_types ) {

		# 'r' = riffle, 'o' = overhand
		my @types = keys %shuffle_types;
		my $type  = $types[ int rand( $n ) ];
		delete $shuffle_types{ $type } unless --$shuffle_types{ $type };

		# shuffle the deck
		_deck_shuffle_riffle( $deck ) if $type eq 'r';
		_deck_shuffle_overhand( $deck ) if $type eq 'o';
	}

	return 1;
}

# -----------------------------------------------------------------------------
# move_card_to( dst, n, opt )
# - moves 'n' card(s) from self to dst - n = 1 (default)
#   - cards are moved one at a time, from the top of self to the top of dst
#   - n eq '*' - move ALL cards
#   - opt:
#     - last_first - move the last card first
# -----------------------------------------------------------------------------
sub move_card_to {
	my ( $self, $dst, $n, $opt ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!

	# make sure our deck have enough cards AND dst is a "deck"
	return 0 unless scalar @$deck;
	return 0 unless $dst->{deck};
	my $deck_dst = $dst->{deck};
	return 0 unless scalar @$deck_dst >= 0;
	
	# init: n
	$n = 1 unless $n;
	$n = scalar @$deck if $n eq '*';
	
	# init options
	$opt = {} unless ref $opt eq 'HASH';
	
	# move the card(s)
	for ( 1..$n ) {
#		unshift @$deck_dst, shift @$deck;
		if ( $opt->{last_first} ) {
			push @$deck_dst, pop @$deck;
		}
		else {
			push @$deck_dst, shift @$deck;
		}
	}
	
	return 1;
}

# -----------------------------------------------------------------------------
# moved_selected_to( dst )
# - moved all selected cards to 'dst' deck
# - unselects on move by default
# - returns number of cards moved
# -----------------------------------------------------------------------------
sub moved_selected_to {
	my ( $self, $dst ) = @_;

	# get deck
	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# make sure our deck have enough cards AND dst is a "deck"
	return 0 unless scalar @$deck;
	return 0 unless $dst->{deck};
	my $deck_dst = $dst->{deck};
	return 0 unless scalar @$deck_dst >= 0;

	# move selected cards to 'dst' / create a new source deck
	my @deck_src;
	my $nselect = 0;
	while ( my $card = shift @$deck ) {
		
		# move selected card
		if ( $card->{select} ) {
			$card->{select} = 0;
			push @$deck_dst, $card;
			$nselect++;
		}
		
		# save unselected card
		else {
			push @deck_src, $card;
		}
	}
	
	# replace deck with deck_src
	$self->{deck} = \@deck_src;
	
	# return the number of cards moved
	return $nselect;
}

# -----------------------------------------------------------------------------
# get_cards()
# - returns an array of cards
# -----------------------------------------------------------------------------
sub get_cards {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	return $deck;
}

# -----------------------------------------------------------------------------
# get_last_card()
# - returns the last card in the deck
# -----------------------------------------------------------------------------
sub get_last_card {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	return $deck->[ scalar( @$deck ) -1 ];
}

# -----------------------------------------------------------------------------
# get_last_card_value()
# - returns the last card deck's value: eg.: A = 1, 2 = 2, J = 11, K = 13
# -----------------------------------------------------------------------------
sub get_last_card_value {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# return 0 if no cards
	return 0 unless scalar @$deck;
	
	# get value
	my $card = $deck->[ scalar( @$deck ) -1 ];
	return $CRD_RANK{ $card->{rank} }->{value};
}

# -----------------------------------------------------------------------------
# get_first_card_value()
# - returns the first card deck's value: eg.: A = 1, 2 = 2, J = 11, K = 13
# -----------------------------------------------------------------------------
sub get_first_card_value {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# return 0 if no cards
	return 0 unless scalar @$deck;
	
	# get value
	my $card = $deck->[ 0 ];
	return $CRD_RANK{ $card->{rank} }->{value};
}

# -----------------------------------------------------------------------------
# get_last_card_suit()
# - returns the last card's suit
# -----------------------------------------------------------------------------
sub get_last_card_suit {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# return 0 if no cards
	return 0 unless scalar @$deck;
	
	# get suit
	my $card = $deck->[ scalar( @$deck ) -1 ];
	return $card->{suit};
}

# -----------------------------------------------------------------------------
# get_first_card()
# - returns the first card
# -----------------------------------------------------------------------------
sub get_first_card {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	return $deck->[ 0 ];
}

# -----------------------------------------------------------------------------
# get_first_card_suit()
# - returns the first card's suit
# -----------------------------------------------------------------------------
sub get_first_card_suit {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	# return 0 if no cards
	return 0 unless scalar @$deck;
	
	# get suit
	my $card = $deck->[ 0 ];
	return $card->{suit};
}

# -----------------------------------------------------------------------------
# count()
# - returns the number of cards in the deck
# -----------------------------------------------------------------------------
sub count {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	return scalar @$deck;
}

# -----------------------------------------------------------------------------
# count_selected()
# - returns the number selected cards in the deck
# -----------------------------------------------------------------------------
sub count_selected {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	my $iselected = 0;
	foreach ( @$deck ) {
		$iselected++ if $_->{select};
	}
	
	return $iselected;
}

# -----------------------------------------------------------------------------
# get_selected()
# - returns an array of all selected cards
# -----------------------------------------------------------------------------
sub get_selected {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	my @cards;
	foreach my $card ( @$deck ) {
		push( @cards, $card ) if $card->{select};
	}
	
	return \@cards;
}

# -----------------------------------------------------------------------------
# unselect()
# - unselects all in the deck
# - returns the number of cards affected
# -----------------------------------------------------------------------------
sub unselect {
	my ( $self ) = @_;

	my $deck = $self->{deck}
		or return -1; # no deck!
	
	my $nselect = 0;
	foreach my $card ( @$deck ) {
		if ( $card->{select} ) {
			$card->{select} = 0;
			$nselect++;
		}
	}
	
	return $nselect;
}

# -----------------------------------------------------------------------------
# ansi_deck()
# - returns an ANSI string, representing each card in the deck
# -----------------------------------------------------------------------------
sub ansi_deck {
	my ( $self ) = @_;
	my $deck = $self->{deck};

#	my $ansi_str = "";
#	foreach my $card ( @$deck ) {
#		my $suit_attrs = $CRD_SUIT{ $card->{suit} };
#		$ansi_str += colored( [ $suit_attrs->{color} ], $card->{rank}, chr $suit_attrs->{symbol} ) + ' ';
#	}
#	
#	return $ansi_str;

	return join( ',', map{ "$_->{rank}$_->{suit}" } @$deck );
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== EXPORT FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# card_color( %card )
# - returns the colour of a standard card hash
# -----------------------------------------------------------------------------
sub card_color {
	my ( $card ) = @_;
	
	# no suit
	return 0 unless $card->{suit};
	
	# use value: odd = red, even = black
	return DECK_CARD_RED
		if ( $CRD_SUIT{ $card->{suit} }->{value} % 2 ) > 0;
	return DECK_CARD_BLACK;
}

# -----------------------------------------------------------------------------
# card_value( %card )
# - returns the value (1-13) of a card in a standard card hash
# -----------------------------------------------------------------------------
sub card_value {
	my ( $card ) = @_;
	
	# no rank
	return 0 unless $card->{rank};
	
	return $CRD_RANK{ $card->{rank} }->{value};
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# _deck_create()
# - create 52 normal playing cards in a deck
# - deck will be in "new deck order"
# -----------------------------------------------------------------------------
sub _deck_create {
	my @deck;

	# go through each suit (in order)
	my $nsuits = scalar keys %CRD_SUIT; # number of suits (usually four...)
	for ( 1..$nsuits ) {
		my $suit_sym = $CRD_SUIT_BYVALUE{ $_ };
		my $suit = $CRD_SUIT{ $suit_sym };

		# go through each rank (in order)
		my $nranks = scalar keys %CRD_RANK;
		foreach ( $suit->{reverse} ? reverse 1..$nranks : 1..$nranks ) {
			my $rank_sym = $CRD_RANK_BYVALUE{ $_ };
			my $rank = $CRD_RANK{ $rank_sym };

			# add a card to the deck
			push @deck, {
				rank => $rank_sym,
				suit => $suit_sym,
			};
		}
	}
	return \@deck;
}

# -----------------------------------------------------------------------------
# _deck_cut()
# - cut the deck into two
# - aim for exactly half +/- SFL_CUT_OFFSET_PERC (percentage)
# -----------------------------------------------------------------------------
sub _deck_cut {
	my ( $deck ) = @_;
	my $ncards = scalar @$deck;

	# 1. find the first card index for the second new deck
	my $deck2_idx = $ncards / 2;

	# uneven number?
	if ( $ncards % 2 ) {
		$deck2_idx = int $deck2_idx; # remove the decimal (round down)
		$deck2_idx += int rand(2); # randomly add 1 or 0 to index
	}

	# 2. add / remove SFL_CUT_OFFSET_PERCentage
	my $offset_cards = int( $deck2_idx / 100 * int rand( SFL_CUT_OFFSET_PERC ) );

	# add / subtract
	$deck2_idx = int rand(2) ? $deck2_idx + $offset_cards : $deck2_idx - $offset_cards;

	# 3. Divide (cut) the deck
	my @deck1 = @$deck[0..($deck2_idx - 2)];
	my @deck2 = @$deck[($deck2_idx - 1)..(scalar @$deck - 1)];

	# 4. Clear original deck / return two decks
	while ( scalar @$deck ) { pop @$deck }
	return( \@deck1, \@deck2 );
}

# -----------------------------------------------------------------------------
# _deck_shuffle_overhand()
#  - performs an overhand shuffle on a deck
#    1. between SFL_OVRHND_PEAL_MIN and SFL_OVRHND_PEAL_MAX cards are pealed
#       off the top and restacked on the new deck upwards
#    2. repeat step 1 until all cards have been used
# -----------------------------------------------------------------------------
sub _deck_shuffle_overhand {
	my ( $deck ) = @_;

	# move the deck
	my @deck_copy;
	while ( @$deck ) {
		push( @deck_copy, shift @$deck );
	}

	# 1. peal and place cards
	while ( @deck_copy ) {

		# random card count to peal off
		my $icards = int rand( ( SFL_OVRHND_PEAL_MAX + 1 ) - SFL_OVRHND_PEAL_MIN );
		$icards += SFL_OVRHND_PEAL_MIN;

		# are there enough cards left?
		$icards = scalar @deck_copy if scalar @deck_copy < $icards;

		# move cards
#		print "move top $icards to new deck...";
		my @tdeck; # temp deck
		while ( $icards-- ) {
#			print '* ';
			push( @tdeck, shift @deck_copy );
		}
		while ( @tdeck ) {
			unshift( @$deck, pop @tdeck );
		}
#		print "\n";
	}
}

# -----------------------------------------------------------------------------
# _deck_shuffle_riffle()
#  -performs a single interleaved riffle shuffle on a deck
#    1. deck is cut, roughly in two
#    2. a random starting side is picked
#    3a. 1 - n cards are taken from first side (n = SFL_RIFFLE_PEAL_MAX)
#    3b. 1 - n cards are taken from the second side and placed ontop of the
#        previous ones
#    4. repeat step 3 untill all cards are used
# -----------------------------------------------------------------------------
sub _deck_shuffle_riffle {
	my ( $deck ) = @_;

	# 1. cut the deck
	my @decks = _deck_cut( $deck );

	# 2. select a starting deck
	my $ideck = int rand(2);

	# 3. process both decks until they are empty
	while ( @decks ) {

		# randomly select how many cards to take
		my $npeal = int( rand(SFL_RIFFLE_PEAL_MAX) ) + 1;

		# are there enough cards left in this deck?
		my $ncards = scalar @{ $decks[ $ideck ] };
		$npeal = $ncards if ( $npeal > $ncards );

		# move cards to new deck
		for ( 1..$npeal ) {
			unshift( @$deck, pop @{ $decks[ $ideck ] } );
		}

		# if deck is empty, delete it
		unless ( @{ $decks[ $ideck ] } ) {
			$ideck ? pop @decks : shift @decks;
		}

		# switch deck (unless only one left)
		if ( scalar @decks > 1 ) {
			$ideck = $ideck ? 0 : 1;
		} else {
			$ideck = 0;
		}
	}
}

# -----------------------------------------------------------------------------
# _print_deck()
# -----------------------------------------------------------------------------
sub _print_deck {
	my ( $deck ) = @_;

	foreach my $card ( @$deck ) {
		my $suit_attrs = $CRD_SUIT{ $card->{suit} };
		print colored( [ $suit_attrs->{color} ], $card->{rank}, chr $suit_attrs->{symbol} ), ' ';
	}
	print "Deck size = ", scalar @$deck, "\n";
}

# - MODULE END ----------------------------------------------------------------
1;
