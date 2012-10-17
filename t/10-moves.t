use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

# start a game.
# make some moves.

my $t = Test::Mojo->new('Cinderblock');
#$t->get_ok('/')->status_is(200)->content_like(qr/Cinderblock/i);

$t->get_ok('/new_game')->status_is(200)->content_like(qr/Sandbox/);
# start a game.
$t->post_form_ok('/new_game', {
      h => 6, w => 6,
      wrap_h => 0, wrap_v => 0,
      play_against => 'invitation',
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
$ws_t->message_is(101);

done_testing;

