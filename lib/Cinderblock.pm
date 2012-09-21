package Cinderblock;
use Mojo::Base 'Mojolicious';
use Mojo::Redis;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');
   
   my $redis; 
  $self->helper (nopubsub_redis => sub{
        return $redis if $redis;
        $redis = Mojo::Redis->new;
        return $redis;
     });
  $self->helper (pubsub_redis => sub{
        return $redis if $redis;
        my $redis = Mojo::Redis->new;
        return $redis;
     });

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/game')->to('game#index');
  $r->websocket('/game/sock')->to('game#game_event_socket');
}

1;
