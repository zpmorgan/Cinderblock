package Cinderblock;
use Mojo::Base 'Mojolicious';

use Mojo::Redis;
#use Protocol::Redis::XS;
our $pub_redis;# = Mojo::Redis->new();
#$pub_redis->timeout(1<<29);
our $getset_redis;# = Mojo::Redis->new();
#$getset_redis->timeout(1<<29);
our $block_redis;# = Mojo::Redis->new(ioloop => Mojo::IOLoop->new);
#$block_redis->timeout(1<<29);

sub mention_on_err_and_close{ 
   my ($self,$redis, $nam) = @_;;
   $redis->on(error => sub{
         my($redis, $error) = @_;
         warn "[REDIS ERROR] $error\n";
         #warn "IOLOOP: ".
         if ($redis->ioloop != Mojo::IOLoop->singleton()){
            warn "stopping extra ioloop?";
            $redis->ioloop->stop;
            $block_redis = undef;
         }
         #warn "IOLOOP singleton: ". Mojo::IOLoop->singleton();
      });
   $redis->on(close => sub{ warn "[$nam REDIS] Close.]";});
}

# This method will run once at server start
sub startup {
   my $self = shift;
   my $app = $self;

   my $config = $self->plugin('JSONConfig');

   $self->secret('$spp->sessions->default_expiration(360000); #100 hours');
   $self->sessions->default_expiration(360000); #100 hours
   # Documentation browser under "/perldoc"
   $self->plugin('PODRenderer');

   my $seeded = 0;

   my $redis; 
   $self->helper (block_redis => sub{
         my $self = shift;
         unless ($seeded){
            srand(time ^ ($$ << 7));
            $seeded = 1;
         }
         return $block_redis if $block_redis;
         $block_redis = Mojo::Redis->new(ioloop => Mojo::IOLoop->new);
         $block_redis->timeout(1<<29);
         $app->mention_on_err_and_close($block_redis, 'block_redis');
         return $block_redis 
      });
   $self->helper (redis_block => sub{
         my $self = shift;
         my @results;
         my $br = $self->block_redis;
         $br->execute(@_, sub{
               my $redis = shift;
               @results = @_;
               $redis->ioloop->stop;
            });
         $block_redis->ioloop->start;
         return $results[0] unless wantarray;
         return @results;
      });
   $self->helper (getset_redis => sub{
      return $getset_redis if $getset_redis;
      $getset_redis = Mojo::Redis->new();
      $getset_redis->timeout(1<<29);
      $app->mention_on_err_and_close($getset_redis, 'getset_redis');
      return $getset_redis;
   });
   $self->helper (pub_redis => sub{
      return $pub_redis if $pub_redis;
      $pub_redis = Mojo::Redis->new();
      $pub_redis->timeout(1<<29);
      $app->mention_on_err_and_close($pub_redis, 'pub_redis');
      return $pub_redis;
   });
   $self->helper (ws_url_base => sub{
         my $self = shift;
         my $ws_url_base = $self->req->url->base;
         $ws_url_base =~ s/^http/ws/;
         unless ($ws_url_base =~ /:\d\d/) {
            $ws_url_base =~ s|$|:3333|;
         }
         return $ws_url_base;
      });

   # Router
   my $r = $self->routes;

   # Normal route to controller
   $r->get('/')->to('game#welcome');
   $r->websocket('/sadchat/')->to('game#sadchat');
   $r->get('/activity/')->to('game#activity');
   $r->get('/new_game/')->to('game#new_game_form');
   $r->post('/new_game/')->to('game#new_game');
   $r->get('/invite/:invite_code/')->to('game#be_invited');
   my $game_r = $r->route('/game/:game_id', game_id => qr/\d+/);
   $game_r->get('')->to('game#do_game');
   $game_r->websocket('sock')->to('game#game_event_socket');
}

1;
