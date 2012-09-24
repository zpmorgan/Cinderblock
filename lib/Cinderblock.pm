package Cinderblock;
use Mojo::Base 'Mojolicious';

use Mojo::Redis;
use Protocol::Redis::XS;
our $pub_redis = Mojo::Redis->new(timeout => 1<<29);
our $getset_redis = Mojo::Redis->new(timeout => 1<<29);
our $block_redis = Mojo::Redis->new(ioloop => Mojo::IOLoop->new, timeout => 1<<29);
{
   no strict 'refs';
   for my $nam (qw/block_redis pub_redis getset_redis/){
      $$nam->on(error => sub{
            my($redis, $error) = @_;
            warn "[$nam REDIS ERROR] $error\n";
         });
   }
}

# This method will run once at server start
sub startup {
   my $self = shift;

   $self->secret('$spp->sessions->default_expiration(360000); #100 hours');
   $self->sessions->default_expiration(360000); #100 hours
   # Documentation browser under "/perldoc"
   $self->plugin('PODRenderer');

   my $redis; 
   $self->helper (block_redis => sub{
         die unless $block_redis;
         srand(time ^ ($$ << 7));
         return $block_redis 
      });
   $self->helper (redis_block => sub{
         my $self = shift;
         my @results;
         $block_redis->execute(@_, sub{
               my $redis = shift;
               @results = @_;
               $redis->ioloop->stop;
            });
         $block_redis->ioloop->start;
         return $results[0] unless wantarray;
         return @results;
      });
   $self->helper (getset_redis => sub{
      return $getset_redis;
   });
   $self->helper (pub_redis => sub{
      return $pub_redis;
   });

   # Router
   my $r = $self->routes;

   # Normal route to controller
   $r->get('/new_game/')->to('game#new_game_form');
   $r->post('/new_game/')->to('game#new_game');
   $r->get('/invite/:invite_code/')->to('game#be_invited');
   my $game_r = $r->route('/game/:game_id', game_id => qr/\d+/);
   $game_r->get('')->to('game#do_game');
   $game_r->websocket('sock')->to('game#game_event_socket');
}

1;
