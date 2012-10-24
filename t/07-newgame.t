use Mojo::Base -strict;

use Test::More;
#use Test::Mojo;
use FindBin '$Bin';
use lib "$Bin/lib";
use Test::Cinderblock;
use Mojo::JSON;
my $json = Mojo::JSON->new;


my ($first_id, $second_id);
{
   my $t = Test::Cinderblock->new('Cinderblock');

   $t->get_ok('/new_game')->status_is(200)->content_like(qr/Sandbox/);
# start a game.
   $t->post_form_ok('/new_game', {
         h => 6, w => 6,
         wrap_h => 0, wrap_v => 0,
         play_against => 'self',
      });
   $t->ua->max_redirects(1); 
   $t->status_is(302);
   my $redir_url = $t->tx->res->headers->location;
   like($redir_url, qr|^http.*game/(\d+)/?$|, 'redirect url for game #');

   $redir_url =~ qr|^http.*game/(\d+)/?$|;
   $first_id = $1;
   #die $first_id;
   cmp_ok($first_id,'>',0, 'game id from redir url is > 0...');

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
}

# same thing from t::c & t::c::g
{
   my $t = Test::Cinderblock->new('Cinderblock');
   my $game = $t->newgame(
      h=>7, wrap_h=>1, wrap_v=>1, w=>10, play_against=>'self'
   );
   $game->game_page_content =~ /ident id (\d+)\b/;
   my $idid = $1;
   cmp_ok ($idid, '>',0 , 'some ident_id is found on the page.');
   like ($game->game_page_content, qr/(anon-$idid)\b.*\1\b/s, 
      'correct anon id is present twice.');
   
   $second_id = $game->id;
   is($second_id, $first_id + 1,  'game ids seem to increment.');
   isa_ok($game, 'Test::Cinderblock::Game', 'newgame is a test::cinderblock::game');
   isa_ok($game->sock, 'Mojo::Transaction::WebSocket');
   my $first_msg = $game->block_sock;
   is_deeply( $json->decode($first_msg), {event_type => 'hello', hello=>'hello'},
      'game does block the sock, first event is a hello.');
}

done_testing;
