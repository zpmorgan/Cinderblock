use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

# start a game.
# make some moves.

{
   my $t = Test::Mojo->new('Cinderblock');
   #$t->get_ok('/')->status_is(200)->content_like(qr/Cinderblock/i);

   $t->get_ok('/new_game')->status_is(200)->content_like(qr/Sandbox/);
   # start a game.
   $t->post_form_ok('/new_game', {
         h => 6, w => 6,
         wrap_h => 0, wrap_v => 0,
         play_against => 'self',
      });
   # my $newgame_res = $t->tx->res;
   # die $newgame_res->code; #302
   $t->ua->max_redirects(1); 
   $t->status_is(302);
   my $redir_url = $t->tx->res->headers->location;
   like($redir_url, qr|^http.*game/(\d+)/?$|, 'redirect url for game #');
   #$redir_url =~ qr|^http.*game/(\d+)/?$|;
   #die $1;

   $t->get_ok($redir_url, 'game url');
   $t->status_is(200, 'game page 200');
   $t->content_like( qr/setupViewOnCanvas/, 'game page: some js at least.');
   $t->element_exists( 'canvas#goban', 'canvas goban exists');
   $t->element_exists('html head title', 'has a title');

   $t->content_like(qr/ws_url:\s*"(.*)",\s*\n/, 'page has websock url in content.');
   $t->tx->res->body =~ /ws_url:\s*"(.*)",\s*\n/;
   my $ws_url = $1;
   ok($ws_url, 'content contains a websocket url.');

   my $ws_t = $t->websocket_ok($ws_url, "open a websocket on $ws_url");
   $ws_t->status_is(101);
   my $msg = $ws_t->_message;
   is_deeply(Mojo::JSON->decode($msg), {event_type => 'hello',hello=>'hello'},
      'event is a hello.');
   #$ws_t->message_is(101);
   #start testing moves...
   
   my @moves_attempted;
   my @res;

   sub move_attempt{
      my ($color,$node) = @_;
      my $req = {
         action=>'attempt_move',
         move_attempt => {color => $color, node=>$node},
      };
      push @moves_attempted, $req;
      $ws_t->send_ok( Mojo::JSON->encode($req));
   }
   sub response{
      my $t = shift;
      my $msg = $t->_message;
      my $res = Mojo::JSON->decode($msg);
      push @res,$res;
      return $res;
   }

   move_attempt( b => [0,1]);
   move_attempt( w => [0,0]);
   move_attempt( b => [1,0]);
   response($ws_t) for (1..3);

   my $delta1 = $res[0]{delta};
   for(0..2){
      is($res[$_]{type}, 'move', "move $_ near corner");
      is(ref $res[$_]{delta}, 'HASH', "delta in res is hash.");
   }
   is_deeply($res[0]{delta}{board}{remove}, undef, 'delta; dirst move, no remove');
}
done_testing;
__END__
   is_deeply($res[0]{delta}{add}, [[b=>[0,1]]], 'delta 1, add one');
   is_deeply($res[1]{delta}{remove}, [], 'delta; move 2, no remove');
   is_deeply($res[1]{delta}{add}, [[w=>[0,0]]], 'delta 2, add one');
   is_deeply($res[2]{delta}{remove}, [[w=>[0,0]]], 'delta; move 3, remove a w');
   is_deeply($res[2]{delta}{add}, [[b=>[1,0]]], 'delta 3, add one b');

   #delta is to have turn & capture changes.
   is_deeply($res[0]{delta}{turn}, {before => 'b', after => 'w'}, 'delta has turn.');
   is_deeply($res[1]{delta}{turn}, {before => 'w', after => 'b'}, 'delta has turn.');
   is_deeply($res[2]{delta}{turn}, {before => 'b', after => 'w'}, 'delta has turn.');
   is($res[0]{delta}{captures}, undef, 'delta capturs isn\'t defined if no captures.');
   is($res[1]{delta}{captures}, undef, 'delta capturs isn\'t defined if no captures.');
   is_deeply($res[0]{delta}{captures}, {
         before => {b=>0,w=>0}, 
         after => {b=>1,w=>0}
      }, 'capturing event delta has captures.');

   use Data::Dumper;
#   die Dumper $res[2];
}
done_testing;
__END__
   $ws_t->send_ok( json_move_attempt( w => [0,0]), 'expertly opening move by w');
   $res = decoded_response($ws_t);
   $ws_t->send_ok( json_move_attempt( b => [1,0]), 'capture');
   $res = decoded_response($ws_t);
   is_deeply($res->{captures}, {b => 1});

   my @move_nodes = ( # 6x6, black starts.
      [0,1],
      [0,0],
      [1,0],
      [0,0],#fail.still w's turn.
   );
   my $turn = 'b';
   for my $node (@move_nodes){
      my $req = {
         action=>'attempt_move',
         move_attempt => {color => $turn, node=>$node},
      };
      $ws_t->send_ok( Mojo::JSON->encode($req), 'send move request');
      my $msg = $
      $ws_t->( Mojo::JSON->encode($req), 'send move request');
   }
}
if(0) {
   my $t = Test::Mojo->new('Cinderblock');
   $t->post_form_ok('/new_game', {
         h => 6, w => 6,
         wrap_h => 0, wrap_v => 0,
         play_against => 'invitation',
      });
}
done_testing;

