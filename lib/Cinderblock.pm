package Cinderblock;
use Mojo::Base 'Mojolicious';
use Cinderblock::Model;
use Mojo::JSON;
my $json = Mojo::JSON->new();

our $VERSION = 0.11;

our $model = Cinderblock::Model->instance;
use Carp;

# This method will run once at server start
sub startup {
   my $self = shift;
   my $app = $self;

   my $config = $self->plugin('JSONConfig');

   $self->secret('$skppxa>adsions->default_expikcvion(3fs00); #100 foos');
   $self->sessions->default_expiration(36000000); #10000 hours
   # Documentation browser under "/perldoc"
   $self->plugin('PODRenderer');

   $self->helper (model => sub{
      # it's a singleton
      return $model;
   });

   #get or generate a unique id for this session
   $self->helper(sessid => sub{
      my $self = shift;
      my $sessid = $self->session('session_id');
      unless ($sessid){
         $sessid = $self->redis_block(incr => 'next_session_id');
         $self->session(session_id => $sessid);
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

   $self->helper (redis_block => sub{
         my $self = shift;
         my @results = $self->model->redis_block(@_);
         return $results[0] unless wantarray;
         return @results;
      });

   $self->helper (pub_redis => sub{
         my $self = shift;
         return $self->model->pub_redis;
      });
   $self->helper (getset_redis => sub{
         my $self = shift;
         return $self->model->getset_redis;
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

   Mojo::IOLoop->recurring(10 => sub{
         $self->model->pub_redis->publish('DONTDIEONME', 'ping');
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
   $r->get('/about')->to('game#about');
   $r->get('/activity/')->to('game#activity');
   $r->get('/new_game/')->to('game#new_game_form');
   $r->post('/new_game/')->to('game#new_game');
   $r->get('/invite/:invite_code/')->to('game#be_invited');
   my $game_r = $r->route('/game/:game_id', game_id => qr/\d+/);
   $game_r->get('')->to('game#do_game');
   $game_r->websocket('sock')->to('game#game_event_socket');

   #another controller.
   $r->websocket('/happy/:channel')->to('happy#happychat');
}

1;
