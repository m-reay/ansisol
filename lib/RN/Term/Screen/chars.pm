package RN::Term::Screen::chars;
#  chars.pm
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
use Term::ReadKey;
use constant;
use Exporter qw/import/;

# -----------------------------------------------------------------------------
# CONST: ASCII Codes
# -----------------------------------------------------------------------------
my %const_ascii = (

	# graphic characters
	ASC_CROSS_DI => 0x2573, # diagonal cross, big X
	ASC_DOTS_LO  => 0x2591, # low density dotted
	ASC_DOTS_MED => 0x2592, # medium density dotted
	ASC_DOTS_HI  => 0x2593, # high density dotted

	# single lines:
	ASC_1LN_HRZ => 0x2500, # horizontal
	ASC_1LN_VRT => 0x2502, # vertical
	
	# thick lines:
	ASC_TLN_HRZ => 0x2501,

	# single line corners (sharp):
	ASC_1LN_CTL => 0x250C, # top left
	ASC_1LN_CTR => 0x2510, # top right
	ASC_1LN_CBL => 0x2514, # bottom left
	ASC_1LN_CBR => 0x2518, # bottom right
	
	# thick Horizontal line corners (sharp):
	ASC_THZ_CTL => 0x250D,
	ASC_THZ_CTR => 0x2511,
	ASC_THZ_CBL => 0x2515,
	ASC_THZ_CBR => 0x2519,

	# single line corners (round):
	ASC_1LN_RTL => 0x256D,
	ASC_1LN_RTR => 0x256E,
	ASC_1LN_RBL => 0x2570,
	ASC_1LN_RBR => 0x256F,

	# playing card suits (solid):
	ASC_SPD_SOL => 0x2660,
	ASC_CLB_SOL => 0x2663,
	ASC_HRT_SOL => 0x2665,
	ASC_DMD_SOL => 0x2666,

	# playing card suits (outline):
	ASC_SPD_OUT => 0x2664,
	ASC_CLB_OUT => 0x2667,
	ASC_HRT_OUT => 0x2661,
	ASC_DMD_OUT => 0x2662,
);

# -----------------------------------------------------------------------------
# CONST: Key Codes / VT2XX Scan Codes
# -----------------------------------------------------------------------------
my %const_keys = (
	# case-insensitive key codes (match one code in array)
	KBD_A => [ ord 'A', ord 'a' ],
	KBD_B => [ ord 'B', ord 'b' ],
	KBD_C => [ ord 'C', ord 'c' ],
	KBD_D => [ ord 'D', ord 'd' ],
	KBD_Q => [ ord 'Q', ord 'q' ],

	# VT220 keyboard scan codes (match a series of codes)
	VT2XX_KEY_ESC  => { scan => [ 0x1B ] },
	VT2XX_KEY_F1   => { scan => [ 0x1B, 0x4F, 0x50 ] },
	VT2XX_KEY_F2   => { scan => [ 0x1B, 0x4F, 0x51 ] },
	VT2XX_KEY_F3   => { scan => [ 0x1B, 0x4F, 0x52 ] },
	VT2XX_KEY_F4   => { scan => [ 0x1B, 0x4F, 0x53 ] },
	VT2XX_KEY_F5   => { scan => [ 0x1B, 0x5B, 0x31, 0x35, 0x7E ] },
	VT2XX_KEY_F6   => { scan => [ 0x1B, 0x5B, 0x31, 0x37, 0x7E ] },
	VT2XX_KEY_F7   => { scan => [ 0x1B, 0x5B, 0x31, 0x38, 0x7E ] },
	VT2XX_KEY_F8   => { scan => [ 0x1B, 0x5B, 0x31, 0x39, 0x7E ] },
	VT2XX_KEY_F9   => { scan => [ 0x1B, 0x5B, 0x32, 0x30, 0x7E ] },
	VT2XX_KEY_F10  => { scan => [ 0x1B, 0x5B, 0x32, 0x31, 0x7E ] },
	VT2XX_KEY_F11  => { scan => [ 0x1B, 0x5B, 0x32, 0x33, 0x7E ] },
	VT2XX_KEY_F12  => { scan => [ 0x1B, 0x5B, 0x32, 0x34, 0x7E ] },
	VT2XX_KEY_UP   => { scan => [ 0x1B, 0x5B, 0x41 ] },
	VT2XX_KEY_DOWN => { scan => [ 0x1B, 0x5B, 0x42 ] },
	VT2XX_KEY_RIGHT=> { scan => [ 0x1B, 0x5B, 0x43 ] },
	VT2XX_KEY_LEFT => { scan => [ 0x1B, 0x5B, 0x44 ] },
	
	# VT220 keyboard scan codes (prefix modifiers)
	VT2XX_MOD_SHIFT      => { mod => [ 0x31, 0x3B, 0x32 ] },
	VT2XX_MOD_ALT        => { mod => [ 0x31, 0x3B, 0x33 ] },
	VT2XX_MOD_ALT_SHIFT  => { mod => [ 0x31, 0x3B, 0x34 ] },
	VT2XX_MOD_CTRL       => { mod => [ 0x31, 0x3B, 0x35 ] },
	VT2XX_MOD_CTRL_SHIFT => { mod => [ 0x31, 0x3B, 0x36 ] },
	VT2XX_MOD_CTRL_ALT   => { mod => [ 0x31, 0x3B, 0x37 ] },
	# E.g:
	# LEFT = 0x1B, 0x5B, 0x44
	# F5   = 0x1B, 0x5B, 0x31, 0x35, 0x7E
	# CTRL = 0x31, 0x3B, 0x35
	#
	# code == 5: F5
	# 1. first 4b (key) = 0x1B, 0x5B, 0x31, 0x35
	# 2. last 2b (mod)  = 0x3B, 0x35
	# 3. last 1b (key)  = 0x7E
	# = 1B 5B 31 35 3B 35 7E
	#
	# code == 3: LEFT
	# 1. first 2b (key) = 0x1B, 0x5B
	# 2. all 3b (mod)   = 0x31, 0x3B, 0x35
	# 3. last 1b (key)  = 0x44
	# = 1B 5B 31 3B 35 44
);

# import constants and export all
constant->import( \%const_ascii );
constant->import( \%const_keys );
our %EXPORT_TAGS = ( const => [ keys %const_ascii, keys %const_keys ] );
our @EXPORT_OK   = ( keys %const_ascii, keys %const_keys,
					qw{ kbd_char_match kbd_key_mod empty_readkey_buffer } );

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# --== PUBLIC FUNCTIONS ==-----------------------------------------------------
# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

# -----------------------------------------------------------------------------
# kbd_key_mod( $mod, $code )
#   - applies a key modifier to a keyboard scan code, such as CTRL, ALT, SHIFT
#   - returns a modified scan code or the original key
# -----------------------------------------------------------------------------
sub kbd_key_mod {
	my ( $mod, $code ) = @_;
	my @new_code;

	# make sure this is a VT2XX scan code / modifier is of correct type
	return $code unless ref $code eq 'HASH' && exists $code->{scan};
	return $code unless ref $mod eq 'HASH' && exists $mod->{mod};

	# get scan code and length
	my $scan_code = $code->{scan};
	my $ncode = scalar @$scan_code;
	
	# get modifier and length
	my $mod_code = $mod->{mod};
	my $nmod = scalar @$mod_code;

	# 5 byte scan code
	if ( $ncode == 5 ) {
		# 1. copy first 4b from scan code
		@new_code = map{ $scan_code->[$_] } (0..3);
		# 2. copy last 2b from modifier
		map{ push @new_code, $mod_code->[$_] } (($nmod-2)..($nmod-1));
		# 3. copy last 1b from scan code
		push @new_code, $scan_code->[$ncode-1];
	}
	
	# 3 byte scan code
	elsif ( $ncode == 3 ) {
		# 1. copy first 2b from scan code
		@new_code = map{ $scan_code->[$_] } (0..1);
		# 2. copy all from modifier
		map{ push @new_code, $mod_code->[$_] } (0..($nmod-1));
		# 3. copy last 1b from scan code
		push @new_code, $scan_code->[$ncode-1];
	}

	# return modified code
	return { scan => \@new_code } if scalar @new_code;
	
	# return unmodified code
	return $code;
}

# -----------------------------------------------------------------------------
# kbd_char_match( @$scan_code, @key_match )
#   - checks if $key_code matches one or more assosiated key codes
#   - returns 1 if match found
# -----------------------------------------------------------------------------
sub kbd_char_match {
	my ( $scan_code, @key_match ) = @_;

	# return if scan code is NOT an array
	return -1 unless ref $scan_code eq 'ARRAY';
	my $scan_code_len = scalar @$scan_code;

	# test all key_match possibilities
	foreach my $match_test ( @key_match ) {
		
		# test for a "scan code"?
		if ( ref $match_test eq 'HASH' && defined $match_test->{scan} ) {
			my $scan_match = $match_test->{scan};
			
			# skip if scan_code length != to match_scan length
			next unless $scan_code_len == scalar @$scan_match;
			
			# test each character
			my $i;
			for ( $i = 0; $i < $scan_code_len; $i++ ) {
				last unless ord $scan_code->[ $i ] == $scan_match->[ $i ];
			}
			
			# match found!
			return 1 if $i == $scan_code_len;
		}
		
		# test for a single match
		else {
			# skip if scan_code is NOT a single character
			next if $scan_code_len > 1;
			
			# char to check
			my $key_code = $scan_code->[0];
			
			# always use an array for the codes were testing against
			$match_test = [ $match_test ] unless ref $match_test eq 'ARRAY';
			
			# test for a match
			foreach my $code ( @$match_test ) {

				# match found!
				return 1 if ord $key_code == $code;
			}
		}
	}

	# no match
	return 0;
}

# -----------------------------------------------------------------------------
# empty_readkey_buffer( @chars )
#   - returns an array ref of characters from the buffer
# -----------------------------------------------------------------------------
sub empty_readkey_buffer {
	my @chars = @_;
	while ( defined ( my $key = ReadKey(-1) ) ) {
		push @chars, $key;
	}
	return \@chars;
}

1;

# vim: shiftwidth=4 tabstops=4 ft=perl
