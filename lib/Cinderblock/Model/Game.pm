package Cinderblock::Model::Game;
use Modern::Perl;
use 5.16.0;
use Moose;
use Mojo::Redis;
use Mojo::JSON;
my $json = Mojo::JSON->new();

has data => (
   is => 'rw',
   isa => 'HashRef',
);

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
   die unless $json_data;
   my $data = $json->decode($json_data);
   $data->{id} = $id; #foo
   return __PACKAGE__->new(data => $data);
}

#store. Always try this after changing stuff.
sub update{
   my $self = shift;
   my $id = $self->data->{id};
   # don't let invalid turns go through. it's 'w','b', or 'none'
   die "turn ". $self->data->{turn} unless ($self->data->{turn} =~ /^(none|[wb])$/);
   $self->model->redis_block(HSET => game => $id => $json->encode($self->data));
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

sub push_event{
   my ($self,$event) = @_;
   push @{$self->data->{game_events}}, $event;
   my $id = $self->id;
   $self->model->pub_redis->publish("game_events:$id" => $json->encode($event));
}

sub is_doubly_passed{
   my $self = shift;
   return 0 if @{$self->data->{game_events}} < 2;
   for(-2..-1){
      return 0 if $self->data->{game_events}->[$_]->{type} ne 'pass';
   }
   return 1
}

1;
