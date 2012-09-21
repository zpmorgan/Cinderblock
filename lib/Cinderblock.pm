package Cinderblock;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/game')->to('game#index');
  $r->websocket('/game/sock')->to('game#game_event_socket');
}

1;
