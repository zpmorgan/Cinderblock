use Mojo::Base -strict;

use Test::More;
#use Test::Mojo;
use FindBin '$Bin';
use lib "$Bin/lib";
use Test::Cinderblock;

use Mojo::JSON;
my $json = Mojo::JSON->new;

# start a game.
# make some moves.
{
   my $t = Test::Cinderblock->new('Cinderblock');
   my $game = $t->newgame; # default 6x6 self planar.

   my $hello = $game->decoded_block_sock;
   is_deeply($hello, {event_type => 'hello',hello=>'hello'},
      'event is a hello.');

   #start testing moves...
   my @moves_attempted = map {$game->do_move_attempt(@$_)} (
      [b => [0,1]],
      [w => [0,0]],
      [b => [1,0]], #cap
   );
   my @res = map{ $game->decoded_block_sock() } (1..3);

   use Data::Dumper;
#   die Dumper $res[0];

   my $delta1 = $res[0]{delta};
   for(0..2){
      is($res[$_]{type}, 'move', "move $_ near corner");
      is(ref $res[$_]{delta}, 'HASH', "delta in res is hash.");
   }
   is_deeply($res[0]{delta}{board}{remove}, undef, 'delta; dirst move, no remove');
   is_deeply($res[0]{delta}{board}{add}, {b => [[0,1]]}, 'delta; first move, add 1 b');
   is_deeply($res[0]{delta}{turn}, {before=>'b', after=>'w'}, 'delta; turn, b to w');
   is_deeply($res[0]{delta}{captures}, undef, 'first move; no captures (!defined)');
}
done_testing;
