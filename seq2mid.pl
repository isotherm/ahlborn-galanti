# Copyright (C) 2014 Kirk Meyer [kirk@meyermail.org]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use File::Format::RIFF;
use MIDI;

my ($name, $file) = @ARGV;
die "Filename required" if( not defined $name );

open( IN, $name ) or die "Could not open file: $!";
binmode IN;
my $lines = join( '', <IN> );
close( IN );

# Work around RIFF library, which doesn't allow nested RIFF chunks.
$lines =~ s/RIFF/LIST/g;
$lines =~ s/\ALIST/RIFF/;

open( DUMMY, '<', \$lines );
my $riff = File::Format::RIFF->read( \*DUMMY );
close( DUMMY );

my @tracks;
foreach my $chunk ( $riff->data )
{
   next if( $chunk->id ne 'LIST' );
   # Embedded RIFF (sqf0)
   foreach my $chunk2 ( $chunk->data )
   {
      next if( $chunk2->id ne 'LIST' );
      # LIST (trks)
      foreach my $chunk3 ( $chunk2->data )
      {
         next if( $chunk3->id ne 'trkc' );
         push( @tracks, $chunk3->data );
      }
   }
}
die "Did not find any tracks in SEQ file!" if( @tracks == 0 );

# I'm not sure if this is the correct PPQM.
my $midi = MIDI::Opus->new( { 'format' => 0, 'ticks' => 384 } );
foreach( @tracks )
{
   my @words = unpack( '(A4)*' );
   # Only export the actual music (tracks 0, 1, 2).
   my $channel = unpack( 'C', $words[0] );
   next if( $channel > 2 );
   
   my @track;
   my $curtime = 0;
   my $curvelocity = 0;
   my $curnote = 0;
   my @track;
   foreach my $word ( @words )
   {
      my $command = (unpack( 'C*', $word ))[3];
      if( $command == 0x40 )
      {
         # Make the time a full 32-bit integer for conversion.
         $curtime = unpack( 'V', substr( $word, 0, 3 ).chr( 0 ) );
      }
      elsif( $command == 0x04 )
      {
         ($channel, $curvelocity, $curnote) = unpack( 'CCC', $word );
      }
      elsif( $command == 0x44 )
      {
         my ($delta) = unpack( 'v', $word );
         push( @track, ['note', $curtime, $delta, $channel, $curnote, $curvelocity] );
      }
   }      
   push $midi->tracks_r, MIDI::Track->new( { 'events' => MIDI::Score::score_r_to_events_r( \@track ) } );
}

die "Not a SEQ file!" if( $name !~ s/\.seq$/.mid/i );
$midi->write_to_file( $name );
