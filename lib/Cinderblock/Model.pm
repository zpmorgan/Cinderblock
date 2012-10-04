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
         $redis->ioloop->stop;
         $self->block_redis($self->_new_blocking_redis);
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

sub game_role_ident{ # ($game_id, 'w'
   my ($self,$game_id, $role) = @_;
   #my $game_json = $self->redis_block(HGET => game => $game_id);
   #my $game = $json->decode($game_json);
   my $game_roles_json = $self->redis_block(HGET => game_roles => $game_id);
   #say $game_id;
   #say $game_roles_json ;
   my $game_roles = $json->decode($game_roles_json);
   my $sessid = $game_roles->{$role};
   #say $sessid ;
   return unless $sessid;
   my $ident_id = $self->redis_block(HGET => session_ident => $sessid);
   #say $ident_id;
   return unless $ident_id;
   my $ident = $self->redis_block(HGET => ident => $ident_id);
   #say $ident;
   return $json->decode($ident);
}


1;
