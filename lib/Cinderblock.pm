package Cinderblock;
use Mojo::Base 'Mojolicious';
use Cinderblock::Model;
use Mojo::JSON;
my $json = Mojo::JSON->new();

use Mojo::Redis;
#use Protocol::Redis::XS;
our $pub_redis;# = Mojo::Redis->new();
#$pub_redis->timeout(1<<29);
our $getset_redis;# = Mojo::Redis->new();
#$getset_redis->timeout(1<<29);
our $block_redis;# = Mojo::Redis->new(ioloop => Mojo::IOLoop->new);
#$block_redis->timeout(1<<29);
our $model;

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

   $self->secret('$skppxa>sessions->default_expiration(360000); #100 hours');
   $self->sessions->default_expiration(360000); #100 hours
   # Documentation browser under "/perldoc"
   $self->plugin('PODRenderer');

   #get or generate a unique id for this session
   $self->helper(sessid => sub{
      my $self = shift;
      my $sessid = $self->session('session_id');
      unless ($sessid){
         $sessid = $self->redis_block(incr => 'next_session_id');
         $self->session(session_id => $sessid);
         $self->redis_block(SET => "session:$sessid" => '{}');
      }
      return $sessid;
   });
   $self->helper(ident => sub{ # ident : find or create-pseudo
      my $self = shift;
      my $ident = $self->stash('ident');
      return $ident if $ident;
      my $ident_id = $self->session('ident_id');
      if($ident_id){
         $ident = $self->redis_block(HGET => 'ident', $ident_id);
         $ident = $json->decode($ident);
         $self->stash(ident => $ident);
         return $ident;
      }
      my $sessid = $self->sessid;
      # generate pseudo :/
      $ident = $self->model->new_anon_ident(sessid => $sessid);
      $self->session(ident_id => $ident->{id});
      $self->stash(ident => $ident);
      return $ident;
   });
   $self->helper(logged_in => sub{ # has ident . not a pseudo
         my $self = shift;
         return 0 unless $self->session('ident_id');
         # still could be an anon ident.
         my $ident = $self->ident;
         return ($ident->{anon} ? 0 : 1);
      });

   my $seeded = 0;
   my $redis; 
   $self->helper (block_redis => sub{
         my $self = shift;
         unless ($seeded){
            srand(time ^ ($$ << 7));
            $seeded = 1;
         }
         return $block_redis if ($block_redis && $block_redis->connected);
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
   $self->helper (model => sub{
      return $model if $model;
      $model = Cinderblock::Model->new();
      return $model;
   });

   # Router
   my $r = $self->routes;

   # auth stuff:
   $r->get('/login/')->to('auth#login');
   $r->get('/logout/')->to('auth#logout');
   $r->get('/openid_login/:oid_provider')->to('auth#openid_login');
   $r->get('/openid_return/')->to('auth#openid_return');
   $r->any('/profile/')->to('auth#profile');

   # routes to game controller
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
