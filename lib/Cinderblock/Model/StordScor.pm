package Cinderblock::Model::StordScor;
use Modern::Perl;
use 5.16.0;
use Moose;
use Mojo::Redis;
use Mojo::JSON;
my $json = Mojo::JSON->new();
use Data::Dumper;

# initialize this with game_id or game

has data => (
   isa => 'HashRef',
   is => 'rw',
   builder => '_get_data',
   lazy => 1,
);

has game_id => (
   isa => 'Int',
   is => 'ro',
   builder => '_game_id_from_game',
   lazy => 1,
);

has game => (
   isa => 'Cinderblock::Model::Game',
   is => 'ro',
   builder => '_game_from_game_id',
   lazy => 1,
);
has model => (
   is => 'ro',
   default => sub{Cinderblock::Model->instance},
);

has scorable => (
   isa => 'Games::Go::Cinderblock::Scorable',
   is => 'ro',
   builder => '_build_scorable',
);

around BUILDARGS => sub{
   my $orig = shift;
   my $class = shift;
   my %args = @_;
   if (defined($args{game}) || defined($args{game_id})){
      return $class->$orig(@_);
   }
   die 'must define game or game_id.';
};

sub _build_scorable{
   my $self = shift;
   my $game = $self->game;
   my $state = $game->state;
   my $scorable = $state->scorable;
   my $deads_hash = $self->data->{dead};
   my @known_dead_nodes;
   for (values %$deads_hash){
      push @known_dead_nodes, @$_;
   }
   for (@known_dead_nodes){
      $scorable->deanimate($_);
   }
   return $scorable;
}

sub _game_from_game_id{
   my $self = shift;
   return $self->model->game($self->game_id)
}
sub _game_id_from_game{
   my $self = shift;
   return $self->game->id;
}

sub r_id{
   my $self = shift;
   return $self->data->{r_id} // 0
}

sub redis_data_key{
   my $self = shift;
   return "scorable:" . $self->game_id;
}
sub redis_game_event_channel{
   my $self = shift;
   return "game_events:" . $self->game_id;
}

# here we clamp with a WATCH
sub _get_data{
   my $self = shift;
   my $scorkey = $self->redis_data_key;
   $self->model->block_redis->watch($scorkey);
   my $ss = $self->model->decoded_redis_block(GET => $scorkey);
   unless ($ss){
      #generate a new one...
      return $self->_gen_and_store_new_data;
   }
   if($ss->{move_hash} ne $self->game->move_hash){
      # a new move has been made?
      #generate another new one...
      return $self->_gen_and_store_new_data;
   }
   return $ss;
}

sub _data_from_some_scorable{
   my ($self,$scorable) = @_;
   my $data = {
      r_id => $self->model->next_stordscor_r_id,
      move_hash => $self->game->move_hash,
      dame => [$scorable->dame->nodes],
      dead => {
         w => [$scorable->dead('w')->nodes],
         b => [$scorable->dead('b')->nodes],
      },
      terr => {
         w => [$scorable->territory('w')->nodes],
         b => [$scorable->territory('b')->nodes],
      },
      approval => {},
   };
   return $data;
}

sub _gen_and_store_new_data{
   my $self = shift;
   my $game_id = $self->game_id;
   my $game = $self->game;
   my $state = $game->state;
   my $scorable = $state->scorable;
   my $data = $self->_data_from_some_scorable($scorable);
   $self->model->redis_block(SET => $self->redis_data_key => $json->encode($data));
   #die Dumper($data);
   return $data;
}

sub publish{
   my $self = shift;
   my $scorable_event = $self->generate_a_scorable_event;
   $self->model->pub_redis->publish(
      $self->redis_game_event_channel,
      $json->encode($scorable_event)
   );
}
sub generate_a_scorable_event{
   my $self = shift;
   my $scorable_event = {
      type => 'scorable',
      scorable => {
         r_id => $self->r_id,
         dame => $self->data->{dame},
         dead => $self->data->{dead},
         terr => $self->data->{terr},
         approval => $self->data->{approval},
      },
   };
   return $scorable_event;
}

# terr seems to include deads. it should be independent...

sub transanimate{
   my ($self,$node) = @_;
   $self->scorable->transanimate($node);
   $self->all_disapprove();
}
sub update_and_publish{
   my ($self) = @_;
   # key in redis is watched already.
   # multi, set, & exec. only update on success.
   my $new_data = $self->_data_from_some_scorable($self->scorable);
   $new_data->{approval} = $self->{data}{approval};
   my @res = $self->model->redis_block(
      ['MULTI'], # 'OK'
      [SET => $self->redis_data_key => $json->encode($new_data)],
      ['EXEC'],
   );
   my $exec_res = $res[2];
   # $exec_res isa arrayref or undef.
   if($exec_res){ 
      $self->data($new_data);
      my $scorable_event = $self->generate_a_scorable_event;
      $self->model->pub_redis->publish(
         $self->redis_game_event_channel,
         $json->encode($scorable_event)
      );
   }
   else{ say 'exec failed. race condition?'}
}

sub ident_approves{
   my ($self,$ident) = @_;
   die 'no ident approves?' unless $ident;
   my @ident_colors = $self->game->roles_of_ident_id ($ident->{id});
   for (@ident_colors){
      $self->data->{approval}{$_} = 1;
   }
}

sub do_all_approve{
   my $self = shift;
   return 0 unless $self->data->{approval}{w};
   return 0 unless $self->data->{approval}{b};
   return 1;
}

sub all_disapprove{
   my $self = shift;
   $self->data->{approval} = {};
}

# stop watching stordscor like some sort of creeper.
sub DESTROY{
   my $self = shift;
   $self->model->block_redis->unwatch;
}


1;
