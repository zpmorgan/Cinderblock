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
   is => 'ro',
   builder => '_get_data',
   lazy => 1,
);

has id => (
   isa => 'Int',
   is => 'ro',
   builder => '_find_id',
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

sub _find_id{
   my $self = shift;
   return $self->data->{id} // 0
}

sub redis_data_key{
   my $self = shift;
   return "scorable:" . $self->game_id;
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

sub _gen_and_store_new_data{
   my $self = shift;
   my $game_id = $self->game_id;
   my $game = $self->game;
   my $state = $game->state;
   my $scorable = $state->scorable;
   my $data = {
      id => $self->model->next_stordscor_id,
      move_hash => $game->move_hash,
      dame => [$scorable->dame->nodes],
      dead => {
         w => [$scorable->dead('w')->nodes],
         b => [$scorable->dead('b')->nodes],
      },
      terr => {
         w => [$scorable->territory('w')->nodes],
         b => [$scorable->territory('b')->nodes],
      },
   };
   $self->model->redis_block(SET => $self->redis_data_key => $json->encode($data));
   die Dumper($data);
   return $data;
}

sub publish{
   my $self = shift;
   my $scorable_event = $self->generate_a_scorable_event;
   $self->model->pub_redis->publish(
      "game_events: " . $self->game_id => 
      $json->encode($scorable_event)
   );
}
sub generate_a_scorable_event{
   my $self = shift;
   my $scorable_event = {
      type => 'scorable',
      scorable => {
         id => $self->id,
         dame => $self->data->{dame},
         dead => $self->data->{dead},
         terr => $self->data->{terr},
      },
   };
   return $scorable_event;
}

# sub attempt_toggle_stone_state{

=comment

sub FOO_attempt_transanimate{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return $self->crap_out(6) unless $game->status eq 'scoring';
   return $self->crap_out(1) unless $color eq $turn;

   my $parent_scorable_id = $msg->{parent_scorable_id};
   my $scorkey = $self->redis_data_key;
   $self->model->block_redis->watch($scorkey);
   my $scorable_representation = $self->model->redis_block(GET => $scorkey);
   $scorable_representation = $json->decode($scorable_representation);
   unless ($scorable_representation->{id} == $parent_scorable_id){
      return $self->crap_out(7);
   }
   # construct state & g::g::cb::scorable from what's in redis.
   my $state = $game->state;

   my $deads = $scorable_representation->{dead};
   my $dead_ns = $state->rulemap->nodeset;
   for my $known_deads (values %$deads){
      my $ns = $state->rulemap->nodeset(@$known_deads);
      $dead_ns = $dead_ns->union($ns);
   }
   my $scorable_object = $state->scorable;
   $scorable_object->deanimate($dead_ns);
   $scorable_object->transanimate($msg->{node});
   
   my $new_representation = {
      dame => $scorable_object->dame,
      terr => $scorable_object->territory,
      dead => $scorable_object->dead,
   };

   my $nodes_to_kill_initially =
   # success! we are participating..
   my $op = $msg->{operation};
   my $optype = $op->{type}; #toggle? mark_(dead|alive)? approve?
   my $node = $op->{node};
   #somehow atomic & timestamped.
   my $op_result = $game->atomic_score_op($op);
   #if ($op_result){
      # model publishes the operation results if any..
   #}
}

=cut

1;
