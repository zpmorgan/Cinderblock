package Test::Cinderblock;
#use Moose;
use 5.14.0;

use parent 'Test::Mojo';

use Test::Cinderblock::Game;

sub newgame{
   my $self = shift;
   my %args = @_;
   $args{h} //= 6;
   $args{w} //= 6;
   $args{wrap_h} //= 0;
   $args{wrap_v} //= 0;
   $args{play_against} //= 'self';

   my $tx = $self->ua->post_form('/new_game', \%args);
   my $code = $tx->res->code;
   warn "code $code:;;; %args" unless $code == 302;

   my $redir_url = $tx->res->headers->location;

#   like($redir_url, qr|^http.*game/(\d+)/?$|, 'redirect url for game #');
   $redir_url =~ qr|^http.*game/(\d+)/?$|;
   my $game_id = $1;
   warn "redir_url $redir_url" unless $game_id;
   
   #my $websocket = $self->ua->websocket($ws_url
   my $game = Test::Cinderblock::Game->new(
#      ua => $self->ua,
      test_cinderblock => $self,
      id => $game_id,
      game_page_url => $redir_url,
      cookie_jar => $self->ua->cookie_jar,
      #ws_url => $ws_url,
   );
   return $game;
}

1;
