#!/usr/bin/perl -W
use strict;
#  sol
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
# -----------------------------------------------------------------------------
# ANSI Solitaire
# Version: 0.9
# Date:    25/09/2019
# -----------------------------------------------------------------------------
use lib 'lib';
use ANSISol;

=pod
Requires Modules:
-----------------
Term::ANSIScreen
Term::ReadKey
Term::Size
Text::ANSI::Util
=cut

# INIT: Screen
my $sol = new ANSISol()
	or exit( -1 );

# INIT: Game
$sol->game_new()
	unless $sol->in_game();

# RUNTIME: main loop
$sol->game_play();

# DONE:
print "\nGoodbye.\n\n";
