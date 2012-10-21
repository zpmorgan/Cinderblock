package Cinderblock::Model;
#use Modern::Perl;
use 5.16.0;
#use Moose;
use MooseX::Singleton;
use Mojo::Redis;
use Mojo::JSON;
my $json = Mojo::JSON->new();

use Cinderblock::Model::Game;

use Carp qw/confess/;
use Carp::Always;

our $default_timeout = 1<<31;

has FOO_sub_redis => (
   isa => 'Mojo::Redis',
   is => 'rw',
   lazy => 1,
   default => sub{
      my $sr = Mojo::Redis->new()->timeout($default_timeout);
      $sr->on(error => sub{say join '|',grep{defined $_} @_;});
      return $sr;
   },
);
sub sub_redis{
   my $self = shift;
   my $sr = Mojo::Redis->new()->timeout($default_timeout);
   $sr->on(error => sub{say join '|',grep{defined $_} @_;});
   return $sr;
}

has pub_redis => (
   isa => 'Mojo::Redis',
   is => 'rw',
   lazy => 1,
   default => sub{
      my $sr = Mojo::Redis->new()->timeout($default_timeout);
      $sr->on(error => sub{say join ' \o/ PUB! \o/ ',grep{defined $_} @_;});
      return $sr;
   },
);
has getset_redis => (
   isa => 'Mojo::Redis',
   is => 'rw',
   lazy => 1,
   default => sub{
      my $r = Mojo::Redis->new()->timeout($default_timeout);
      $r->ioloop->recurring(60 => sub{$r->get('DONTDIEONME',sub{})});
      $r->on(error => sub{
         my($redis, $error) = @_;
         say "[getset REDIS ERROR!] $error";
      });
      $r->on(close => sub{say 'getset REDIS closes!'});
      $r;
   },
);

has block_redis => (
   isa => 'Mojo::Redis',
   builder => '_new_blocking_redis',
   is => 'rw',
);


sub _new_blocking_redis{
   my $self = shift;
   my $block_redis = Mojo::Redis->new(ioloop => Mojo::IOLoop->new);
   $block_redis->on(close => sub{
         my($redis, $error) = @_;
         say "[blocking REDIS CLOSES!]";
         say "stopping extra ioloop?";
         $redis->ioloop->stop;
         $self->block_redis($self->_new_blocking_redis);
      }); 
   $block_redis->on(error => sub{
         my($redis, $error) = @_;
         say "[blocking REDIS ERROR!] $error";
         say "stopping extra ioloop?";
         # confess;
         $redis->ioloop->stop;
         $self->block_redis($self->_new_blocking_redis);
         confess();
      });
   $block_redis->timeout($default_timeout);
   return $block_redis 
};

sub redis_block{
   my $self = shift;
   my $br = $self->block_redis;
   my @results;
   $br->execute(@_, sub{
         my $redis = shift;
         @results = @_;
         $redis->ioloop->stop;
      });
   $br->ioloop->start;
   return $results[0] unless wantarray;
   return @results;
};


# get game.. 
sub game{
   my ($self,$game_id) = @_;
   return Cinderblock::Model::Game->from_id($game_id);
   my $game = $self->redis_block(hget => game => $game_id);
   $game = $json->decode($game);
   $game = Cinderblock::Model::Game->new(data => $game);
   return $game;
}

# invite: {game_id => $game_id, color => $other_color};
sub invite{
   my ($self,$code) = @_;
   my $invite = $self->redis_block(HGET => invite => $code);
   $invite = $json->decode($invite);
   return $invite;
}

sub recently_active_games{
   my ($self,$n) = @_;
   my $actives = $self->redis_block(ZREVRANGE => 'recently_actives_game_ids', 0,$n-1);
   return @$actives;
}

# get role...
sub game_role_ident{ # ($game_id, 'w'
   my ($self,$game_id, $role) = @_;
   my $game_roles_json = $self->redis_block(HGET => game_roles => $game_id);
   my $game_roles = $json->decode($game_roles_json);
   my $ident_id = $game_roles->{$role};
   return unless $ident_id; #invitee unarrived...
   my $ident = $self->redis_block(HGET => ident => $ident_id);
   return $json->decode($ident);
}

sub new_anon_ident{
   my $self = shift;
   my %opts = @_;
   my $sessid = $opts{sessid};
   die unless $sessid;
   my $ident_id = $self->redis_block(INCR => 'next_ident_id');
   my $username = 'anon-' . $ident_id;
   my $ident = {id => $ident_id, anon => 1, username => $username};
   $self->redis_block(HSET => ident => $ident_id, $json->encode($ident));
   $self->redis_block(HSET => session_ident => $sessid, $ident_id);
   return $ident;
}

1;
