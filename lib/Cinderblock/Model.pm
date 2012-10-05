package Cinderblock::Model;
#use Modern::Perl;
use 5.16.0;
use Moose;
use Mojo::Redis;
use Mojo::JSON;
my $json = Mojo::JSON->new();

has block_redis => (
   isa => 'Mojo::Redis',
   builder => '_new_blocking_redis',
   is => 'rw',
);
use Carp qw/confess/;
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
   $block_redis->timeout(1<<29);
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
# set $role as an ident_id
sub set_game_player{
   my $self = shift;
   my %opts = @_;
   my $ident_id = $opts{ident_id};
   unless($ident_id){
      die 'no session to speak of.' unless $opts{sessid};
      $ident_id = $self->redis_block(HGET => session_ident => $opts{sessid});
      unless(defined $ident_id){
         my $ident = $self->new_anon_ident(sessid => $opts{sessid});
         $ident_id = $ident->{id};
      }
   }
   #my $sessid = $opts{sessid} // $self->sessid;
   my $gameid = $opts{game_id};# // $self->stash('game_id');
   die unless $opts{color} =~ /^(b|w)$/;

   my $roles = $self->redis_block(HGET => game_roles => $gameid);
   $roles = $json->decode($roles);
   $roles->{$opts{color}} = $ident_id;
   $roles = $json->encode($roles);
   $self->redis_block(HSET => game_roles => $gameid, $roles);
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
