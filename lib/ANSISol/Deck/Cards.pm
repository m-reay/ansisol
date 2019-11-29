package ANSISol::Deck::Cards;
#  Cards.pm
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

#
# Rank / Suit Definitions
# card 9 x 7 ( 7 x 5 ) - pattern = 7 x 4
#
use constant {
	
	# Card dimentions (Exported)
	CRD_SIZE_COLS   => 9,
	CRD_SIZE_ROWS   => 7,
	CRD_OFFSET_COLS => 4,
	CRD_OFFSET_ROWS => 2,
	
	# face down card
	CRD_FACE_DOWN   => { rank => '#', suit => '#' },
	
	CRD_RANK_PATTERN => {
		'A' => { 2 => [ 0, 1, 0 ] }, # 3rd row, middle default symbol
		'2' => {
			2 => [ 0, 1, 0 ],
			3 => [ 0, 1, 0 ] },
		'3' => {
			1 => [ 0, 1, 0 ],
			2 => [ 0, 1, 0 ],
			3 => [ 0, 1, 0 ] },
		'4' => {
			1 => [ 1, 0, 1 ],
			4 => [ 1, 0, 1 ] },
		'5' => {
			1 => [ 1, 0, 1 ],
			2 => [ 0, 1, 0 ],
			4 => [ 1, 0, 1 ] },
		'6' => {
			1 => [ 1, 0, 1 ],
			3 => [ 1, 0, 1 ],
			4 => [ 1, 0, 1 ] },
		'7' => {
			1 => [ 1, 0, 1 ],
			2 => [ 0, 1, 0 ],
			3 => [ 1, 0, 1 ],
			4 => [ 1, 0, 1 ] },
		'8' => {
			1 => [ 1, 0, 1 ],
			2 => [ 1, 0, 1 ],
			3 => [ 1, 0, 1 ],
			4 => [ 1, 0, 1 ] },
		'9' => {
			1 => [ 1, 0, 1 ],
			2 => [ 1, 1, 1 ],
			3 => [ 1, 0, 1 ],
			4 => [ 1, 0, 1 ] },
		'10' => {
			1 => [ 1, 0, 1 ],
			2 => [ 1, 1, 1 ],
			3 => [ 1, 0, 1 ],
			4 => [ 1, 1, 1 ] },
	},
	
	CRD_SUIT_STYLE => {
		'S' => { symbol => ASC_SPD_OUT, color => 'bright_white' },
		'C' => { symbol => ASC_CLB_OUT, color => 'bright_white' },
		'H' => { symbol => ASC_HRT_SOL, color => 'bright_red' },
		'D' => { symbol => ASC_DMD_SOL, color => 'bright_red' },
	},
	
	CRD_COLOR            => 'bright_white',
	CRD_COLOR_SELECT     => 'bright_red',
	CRD_COLOR_BACK       => 'blue',
	CRD_SILHOUETTE_COLOR => 'white',
};

# Export functions / constants
our %EXPORT_TAGS = ( const => [ qw/CRD_SIZE_COLS CRD_SIZE_ROWS CRD_OFFSET_COLS CRD_OFFSET_ROWS CRD_FACE_DOWN/ ] );
our @EXPORT_OK = qw/ansi_card text_card CRD_SIZE_COLS CRD_SIZE_ROWS CRD_OFFSET_COLS CRD_OFFSET_ROWS CRD_FACE_DOWN/;

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# ansi_card( card, %opt )
# - converts a card (rank, suit) into an ANSI graphic
#   - opt: card_under: denotes a card under this one
# -----------------------------------------------------------------------------
sub ansi_card {
	my ( $card, $opt ) = @_;
	$opt = {} unless ref $opt eq 'HASH';

	# return a card
	if ( $card && $card->{rank} && $card->{suit} ) {

		# face down
		if ( $card->{rank} eq '#' && $card->{suit} eq '#' ) {
			return _gen_card_face_down();
		}
		
		# face up
		else {
			return _gen_card( $card->{rank}, $card->{suit}, $card->{select},
				$opt->{card_under} );
		}
	}
	
	# return a card placeholder / silhouette
	else {
		return _gen_card_silhouette();
	}
}

# -----------------------------------------------------------------------------
# text_card( card )
# - returns a card name (rank, suit)
# -----------------------------------------------------------------------------
sub text_card {
	my ( $card ) = @_;

	return "$card->{rank}$card->{suit}"
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PRIVATE FUNCTIONS ==----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

#
# _gen_card( rank, suit, select, card_under )
# - generates a single card
#   - rank: S, C, H, D
sub _gen_card {
	my ( $rank, $suit, $select, $card_under ) = @_;
	
	# set the number of symbols to print
	my $n_symbols = $rank;
	$n_symbols = 1 if $rank =~ m/A/i; # Ace = 1
	$n_symbols = 0 unless $n_symbols =~ m/\d+/; # No symbols if not a digit

	# set the card colour
	my $crd_color = $select ? CRD_COLOR_SELECT : CRD_COLOR;

	# get the rank pattern
	my $pattern = CRD_RANK_PATTERN->{ $rank };

	# get the rank length / set the rank color
	my $rank_len = length( $rank ); # char count
		$rank = color( CRD_SUIT_STYLE->{ $suit }->{color} )
			. $rank . color( 'reset' );

	# set the suit symbol and color
	my $symbol = color( CRD_SUIT_STYLE->{ $suit }->{color} )
		. chr( CRD_SUIT_STYLE->{ $suit }->{symbol} ) . color( 'reset' );

	# card_under: thick top line?
	my ( $t_rtl, $t_hrz, $t_rtr ) = ( ASC_1LN_RTL, ASC_1LN_HRZ, ASC_1LN_RTR );
	( $t_rtl, $t_hrz, $t_rtr )    = ( ASC_THZ_CTL, ASC_TLN_HRZ, ASC_THZ_CTR )
		if $card_under;

	# card: top
	my $card = color( $crd_color ) . chr( $t_rtl )
		. chr( $t_hrz ) x 7 . chr( $t_rtr ) . color( 'reset' ) . "\n";

	# card: rank / suit
	$card .= color( $crd_color ) . chr( ASC_1LN_VRT ) . color( 'reset' )
		. $rank . $symbol . ' ' x ( 6 - $rank_len )
		. color( $crd_color ) . chr( ASC_1LN_VRT ) . color( 'reset' ) . "\n";

	# card: pattern
	foreach my $i ( 1..4 ) {
		$card .= color( $crd_color ) . chr( ASC_1LN_VRT )
			. color( 'reset' ) . ' '; # first of 7 spaces
		if ( $pattern->{ $i } ) {
			foreach my $col ( 0..2 ) {
				if ( my $p = $pattern->{ $i }->[ $col ] ) {
					if ( $p =~ m/1/ ) {
						$card .= "$symbol ";
					}
					else {
						$card .= "? ";
					}
				}
				else { $card .= ' ' x 2 }
			}
		}
		else { # nothing on row
			$card .= ' ' x 6;
		}
		$card .= color( $crd_color ) . chr( ASC_1LN_VRT ) . color( 'reset' ) . "\n";
	}

	# card: bottom
	$card .= color( $crd_color ) . chr( ASC_1LN_RBL )
		. chr( ASC_1LN_HRZ ) x 7 . chr( ASC_1LN_RBR ) . color( 'reset' );

	return $card;
}

#
# _gen_card_silhouette( )
# - generates a card placeholder / outline
sub _gen_card_silhouette {

	# card: top / middle / bottom
	my $card = color( CRD_SILHOUETTE_COLOR );
	$card .= chr( ASC_1LN_RTL )
		  .  chr( ASC_1LN_HRZ ) x 7 . chr( ASC_1LN_RTR ) . "\n";
	$card .= ( chr( ASC_1LN_VRT ) . ' ' x 7 . chr( ASC_1LN_VRT ) . "\n" ) x 5;
	$card .= chr( ASC_1LN_RBL )
		  .  chr( ASC_1LN_HRZ ) x 7 . chr( ASC_1LN_RBR );
	$card .= color( 'reset' );
	return $card;
}

#
# _gen_card_face_down( )
# - generates a face-down card
sub _gen_card_face_down {
	
	# card: top / middle / bottom
	my $card .= color( CRD_COLOR ) . chr( ASC_1LN_RTL )
		  .  chr( ASC_1LN_HRZ ) x 7 . chr( ASC_1LN_RTR ) . color('reset') . "\n";
	$card .= ( color( CRD_COLOR ) . chr( ASC_1LN_VRT ) . color('reset')
		. color( CRD_COLOR_BACK ) . chr( ASC_CROSS_DI ) x 7 . color('reset')
		. color( CRD_COLOR ) . chr( ASC_1LN_VRT ) . color('reset') . "\n" ) x 5;
	$card .= color( CRD_COLOR ) . chr( ASC_1LN_RBL )
		  .  chr( ASC_1LN_HRZ ) x 7 . chr( ASC_1LN_RBR ) . color('reset');
	return $card;
}

# - MODULE END ----------------------------------------------------------------
1;
