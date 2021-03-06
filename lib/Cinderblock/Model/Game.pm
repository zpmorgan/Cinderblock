package Cinderblock::Model::Game;
use Modern::Perl;
use 5.16.0;
use Moose;
use Mojo::Redis;
use Mojo::JSON qw(decode_json encode_json);

use Time::HiRes;

has data => (
   is => 'rw',
   isa => 'HashRef',
);
has rulemap => (
   is => 'rw',
   isa => 'Games::Go::Cinderblock::Rulemap',
   lazy => 1,
   builder => '_build_rulemap',
);


has _fresh => (
   isa => 'Bool',
   is => 'ro',
   default => 0,
);
has _fresh_role_idents => (
   isa => 'HashRef',
   is => 'ro',
);

around BUILDARGS => sub {
   my $orig  = shift;
   my $class = shift;
   my %args = @_;

   if ($args{data}){ #data from redis db or something?
      return $class->$orig(@_);
   }

   my %fresh_role_idents = %{$args{roles}} ;
   #$fresh_role_idents{b} = $args{b_role} if $args{b_role};
   #$fresh_role_idents{w} = $args{w_role} if $args{w_role};

   my $game_id = __PACKAGE__->model->redis_block(incr => 'next_game_id');
   my ($h,$w,$wrap_h,$wrap_v) = @args{qw/h w wrap_h wrap_v/};
   my $board = [ map{[map {''} 1..$w]} 1..$h ];
   # TODO: handi
   my $data = {
      id => $game_id,
      game_events => [],
      board => $board,
      w => $w,
      h => $h,
      wrap_v => $wrap_v,
      wrap_h => $wrap_h,
      turn => 'b',
   };
   my $self = $class->$orig( 
      data => $data,
      _fresh => 1,
      _fresh_role_idents => \%fresh_role_idents,
   );
   return $self;
};

sub BUILD{
   my $self = shift;
   if ($self->_fresh){ #just now created? handle roles, store, etc.
      $self->update();
      for my $role_color (keys %{$self->_fresh_role_idents}){
         $self->set_role($role_color, $self->_fresh_role_idents->{$role_color});
      }
   }
}

sub model{
   return Cinderblock::Model->instance;
}

# constructor
sub from_id{
   my $class = shift;
   my $model = Cinderblock::Model->instance;
   my $id = shift;
   die unless $id;
   my $json_data = $model->redis_block(HGET => game => $id);
   return unless $json_data;
   my $data = decode_json($json_data);
   $data->{id} = $id; #foo
   return __PACKAGE__->new(data => $data);
}

#store. Always try this after changing stuff.
sub update{
   my $self = shift;
   my $id = $self->data->{id};
   # don't let invalid turns go through. it's 'w','b', or 'none'
   die "turn ". $self->data->{turn} unless ($self->data->{turn} =~ /^(none|[wb])$/);
   $self->model->redis_block(HSET => game => $id => encode_json($self->data));
}

sub roles{
   my $self = shift;
   my $roles = $self->model->redis_block('HGET',game_roles => $self->id) // '{}';
   return decode_json($roles);
}
sub set_role{
   my $self = shift;
   my $color = shift;
   my $ident_id = shift;
   my $roles = $self->roles;
   $roles->{$color} = $ident_id;
   $self->model->redis_block(HSET => game_roles => $self->id => encode_json($roles));
}

# this returns any colors where role{color} == ident_id
# e.g. ('b','w') in a sandbox game
sub roles_of_ident_id{
   my ($self,$ident_id) = @_;
   my $roles = $self->roles;
   my @colors;
   # grep{defined $_} map {$roles->{$_} // -1 == $ident_id} 
   for (keys %$roles){
      next unless defined $roles->{$_};
      next unless $roles->{$_} == $ident_id;
      push @colors, $_;
   }
   return @colors;
}

#captures, board, & turn describe only the current state. not history.
sub add_captures{
   my ($self, $color,$n) = @_;
   $self->data->{captures}{$color} = 
      $n + ( $self->data->{captures}{$color} // 0) ;
}
# $game->captures($color => $caps_delt->{$color}{after});
sub captures{
   my ($self, $color, $newval) = @_;
   unless ($color){
      return $self->data->{captures};
   }
   die "notacolor $color" unless ($color =~ /^[bw]$/);
   if($newval){
      $self->data->{captures}{$color} = $newval;
   }
   return ( $self->data->{captures}{$color} ) ;
}
sub board {
   $_[0]->data->{board} = $_[1] if $_[1];
   return $_[0]->data->{board}
}
sub winner{
   $_[0]->data->{winner} = $_[1] if $_[1];
   return $_[0]->data->{winner}
}
sub turn{
   $_[0]->data->{turn} = $_[1] if $_[1];
   return $_[0]->data->{turn}
}
sub next_turn{
   return (($_[0]->data->{turn} eq 'w') ? 'b' : 'w');
}

sub id{$_[0]->data->{id}}
sub status{
   my $self = shift;
   my $status = shift;
   $self->data->{status} = $status if $status;
   return $self->data->{status} // 'active'
}
sub set_status_active{shift->status('active')}
sub set_status_scoring{shift->status('scoring')}
sub set_status_finished{shift->status('finished')}
sub w{shift->data->{w}}
sub h{shift->data->{h}}
sub wrap_h{shift->data->{wrap_h}}
sub wrap_v{shift->data->{wrap_v}}

sub game_events_ref {
   return $_[0]->data->{game_events}
}
sub push_event{
   my ($self,$event) = @_;
   push @{$self->data->{game_events}}, $event;
   my $id = $self->id;
   $self->model->pub_redis->publish("game_events:$id" => encode_json($event));
   # for activity page.
   $self->promote_activity();
}

sub is_doubly_passed{
   my $self = shift;
   return 0 if @{$self->data->{game_events}} < 2;
   for(-2..-1){
      return 0 if $self->data->{game_events}->[$_]->{type} ne 'pass';
   }
   return 1
}
sub last_move_was_pass{
   my $self = shift;
   return 0 if @{$self->data->{game_events}} < 1;
   return 0 if $self->data->{game_events}->[-1]->{type} ne 'pass';
   return 1;
}


sub promote_activity{
   my ($self) = @_;
   $self->model->getset_redis->zadd(recently_actives_game_ids => 1000*Time::HiRes::time(), $self->id);
}

sub _build_rulemap{
   my $self = shift;
   my $rulemap = Games::Go::Cinderblock::Rulemap::Rect->new(
      w => $self->w,  h => $self->h,
      wrap_v => $self->wrap_v,
      wrap_h => $self->wrap_h,
   );
   return $rulemap;
}

sub state{
   my $self = shift;
   my $state = Games::Go::Cinderblock::State->new(
      rulemap => $self->rulemap,
      turn => $self->turn,
      board => $self->board,
      captures => $self->captures,
   );
   return $state;
}

sub move_hash{
   my $self = shift;
   my @events = @{$self->data->{game_events}};
   while(@events){
      my $lstmv = pop @events;
      return $lstmv->{move_hash} if  $lstmv->{move_hash};
   }
   return 0;
   return undef
}

sub stordscor{
   my $self = shift;
   return $self->model->stordscor($self->id);
}

1;
