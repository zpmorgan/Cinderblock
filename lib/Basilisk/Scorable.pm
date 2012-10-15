package Basilisk::Scorable;
use Moose;

# Basilisk::Scorable,
# * original Basilisk had death masks & territory masks.
# * B::Scorable should encapsulate that, 
#   & have methods to derive score from caps, deads, & territory

# Rulemap has komi. State has captures. This has dead & territory
# so this module should use those to calc final score.
has rulemap => (
   isa => 'Basilisk::Rulemap',
   is => 'ro', #shouldn't change.
   required => 1,
);
has state => (
   isa => 'Basilisk::State',
   is => 'ro', #shouldn't change.
   required => 1,
);

has _alive => (
   isa => 'HashRef[Basilisk::NodeSet]',
   is => 'ro',
   lazy => 1,
   builder => '_initially_generous_with_life',
);
has _dead => (
   isa => 'HashRef[Basilisk::NodeSet]',
   is => 'ro',
   lazy => 1,
   builder => '_empty_nodesets',
);
has _known_terr => (
   isa => 'HashRef[Basilisk::NodeSet]',
   is => 'ro',
   lazy => 1,
   builder => '_empty_nodesets',
);
has _derived_terr => (
   isa => 'HashRef[Basilisk::NodeSet]',
   is => 'ro',
   lazy => 1,
   builder => '_initial_derived_terr',
);
has _dame => (
   isa => 'Basilisk::NodeSet',
   is => 'ro',
   lazy => 1,
   builder => '_initial_dame',
);

#has _seki => (); #

#based on state, has dame, derived, & alive. that is everything initially.
#this is an attribute so we can initialize these 3 categories at the same time, if needed.
has _initial_cats => (
   is => 'ro',
   isa => 'HashRef', #dame isn't color-separated; the others are.
   lazy => 1,
   builder => '_build_initial_cats',
);

#crawl entire board, putting each node into one of these 3 categories.
sub _build_initial_cats{
   my $self = shift;

   my $remaining_nodes = $self->rulemap->all_nodes_nodeset;
   my %initial_cats = (
      dame => $self->rulemap->nodeset,
      alive => {
         w => $self->rulemap->nodeset,
         b => $self->rulemap->nodeset,
      },
      derived_terr => {
         w => $self->rulemap->nodeset,
         b => $self->rulemap->nodeset,
      },
   );

   my $board = $self->state->board;
   while($remaining_nodes->count){
      my $node = $remaining_nodes->choose;
      my $stone = $self->state->at_node($node);
      if($stone){
         my $cond = sub{ $_ eq $stone};
         my $contiguous = $self->state->floodfill ($cond, $node);
         $remaining_nodes->remove($contiguous);
         $initial_cats{alive}{$stone}->add($contiguous);
      }
      else { #space.
         my $cond = sub{ ! $_ };
         my $contiguous = $self->state->floodfill ($cond, $node);
         my $adjacent = $contiguous->adjacent;
         my @adj_colors = $self->state->colors_in_nodeset($adjacent);;
         if(@adj_colors != 1){
            $initial_cats{dame}->add($contiguous);
         }
         else {
            $initial_cats{derived_terr}{$adj_colors[0]}->add($contiguous);
         }
         $remaining_nodes->remove($contiguous);
      }
   }
   return \%initial_cats;
}
sub _initial_dame{
   my $self = shift;
   return $self->_initial_cats->{dame}
}
sub _initial_derived_terr {
   my $self = shift;
   return $self->_initial_cats->{derived_terr}
}
sub _initially_generous_with_life{
   my $self = shift;
   return $self->_initial_cats->{alive}
}
sub _empty_nodesets{
   my $self = shift;
   return {
      b => $self->rulemap->nodeset,
      w => $self->rulemap->nodeset,
   };
}
   
sub node_animated{
   my ($self,$node) = @_;
}

#transanimation -- to toggle the status of life/death, reanimate^deanimate
#nop if not occupied.

sub transanimate{
   my ($self, $node) = @_;
   my $stone = $self->state->at_node($node);
   return unless $stone;
   my $deanimate = $self->node_animated($node);
   if($deanimate){
      #my $nodeset = $self->rulemap->floodfill(sub{0}, $node);
      $self->deanimate_node($node);
   }
   else{
      $self->reanimate_node($node);
   }
};
sub reanimate_node{ #dead -> alive
   my ($self,$node) = @_;
   my $stone = $self->state->stone_at_node($node);
   die "no stone at @$node..." unless $stone;

   my $bounded_color = ($stone eq 'w') ? 'b' : 'w';
   my $new_ambiguous_space = $self->state->floodfill(sub{$_ ne $bounded_color}, $node);
   my $new_alives = $self->state->grep_nodeset(sub{$_ eq $stone}, $new_ambiguous_space);
   $new_ambiguous_space->remove($new_alives);

   my @amb_spaces = $new_ambiguous_space->disjoint_split;
   
   $new_ambiguous_space == 'dame'? 1:0;
}
sub deanimate_node{ #alive -> dead
   my ($self,$node) = @_;
   my $stone = $self->state->at_node($node);
   die "no stone at @$node..." unless $stone;

   my $bounded_color = ($stone eq 'w') ? 'b' : 'w';
   my $new_known_terr = $self->state->floodfill(sub{$_ ne $bounded_color}, $node);
   my $new_deads = $self->state->grep_nodeset(sub{$_ eq $stone}, $new_known_terr);
   $new_known_terr->remove($new_deads);

   # let's say, illegal if any of our new known terr is already known terr.
   my $illegal = 
         $new_known_terr->intersect($self->_known_terr->{w})->count()
       + $new_known_terr->intersect($self->_known_terr->{b})->count();
   if($illegal) {return}

   #wipe other cats of nodes representing space;
   # non-known territory/space -> known
   $self->_derived_terr->{w}->remove($new_known_terr);
   $self->_derived_terr->{b}->remove($new_known_terr);
   $self->_dame->remove($new_known_terr);
   $self->_known_terr->{$bounded_color}->add($new_known_terr);

   #same for stones: alive -> dead category
   $self->_alive->{$stone}->remove($new_deads);
   $self->_dead->{$stone}->add($new_deads);
}


# these 4 lines are shtoopid.
# a state is used, and a bunch of nodesets are derived. that is all.
# inc. floodfill algorithms to reanimate/deanimate certain chains / chain-groups
#
#sub territory{}
# sub dead_stones{}
#sub territory_board{}
#sub dead_stones_board{}
#
#->dead(color): return a nodeset of dead stones of color.
#->dead: return a hashref of color => nodeset pairs.
sub dead{
   my ($self,$color) = @_;
   unless ($color){
      return {
         b => $self->dead('b'),
         w => $self->dead('w'),
      };
   }
   #have color.
   return $self->_dead->{$color};
}
sub territory{
   my ($self,$color) = @_;
   unless ($color){
      return {
         b => $self->territory('b'),
         w => $self->territory('w'),
      };
   }
   #have color.
   #  die %{$self->_known_terr};
   my $known = $self->_known_terr->{$color};
   die unless $known;
   my $derived = $self->_derived_terr->{$color};
   die unless $derived;
   # TODO: implications of sharing dead stones between multiple other colors.
   my $other_color = $color eq 'b' ? 'w' : 'b';
   my $deads_as_territory = $self->_dead->{$other_color};
   return $known->union($derived)->union($deads_as_territory);
}
sub dame{
   my $self = shift;
   return $self->_dame;
}

1;

__END__

=head1 NAME

Basilisk::Scorable - An abstract state of endgame score negotiation

=head1 SYNOPSIS

   my $rulemap = Basilisk::Rulemap::Rect->new( h=>2, w=>5 );
   my $board = [
      [qw/0 w 0 b b/],
      [qw/0 w w b 0/],
   ];
   my $state_to_score = Basilisk::State->new(
      rulemap  => $rulemap,
      turn => 'b',
      board => $board,
   );
   my $scorable = $state_to_score->scorable;
   my %score = $scorable->score;
   say "black: $score{b}, white: $score{w}";
   # black: 1, white: 2
   
   $scorable->transanimate([0,4]);
   # equivelent: $scorable->deanimate([0,4]);
   my %dead_stones = $scorable->dead;
   say "black: $dead_stones{b}, white: $dead_stones{w}";
   # black: 3, white: 0
   #
   $scorable->reanimate([0,4]);
   # equivelent: $scorable->transanimate([0,4]);
   # score black: 1, white: 2

=head1 DESCRIPTION

The status of each node is one of the following categories:
categories:

=head2 Stone-occupied node categories:

=over 4

=item alive

The initial state.

=item dead

A storable must be told what stones are dead.

=item seki? 

not implemented. Maybe the stones are alive in seki? dunno how to mark seki.

=back

=head2 stoneless node categories:

=over 4

=item   known_territory 

considering stones that are known to be dead, this area is known to be alive.

=item   derived_territory

Surrounded by stones that may be deanimated.

=item   dame

the region is bounded by stones of more than one color.

=item   seki territory?

not implemented. Further research is needed.

=back

I think that this covers all categories related to score negotiation
for different scoring regimes.

=over 4

=item chinese rules -- alive stones are a point each.

=item japanese rules -- no territory in seki.

=back

head1 TERMINOLOGY

=over 4

=item deanimate -- To set as dead, to kill

=item reanimate -- To set as alive, to revive

=item animation -- the life/death state of a stone, chain, group, or any (in)?animate object

=item transanimate -- to animate xor deanimate something, to to toggle the life/death state

=back

=head1 RULES

Empty regions are initially either dame or derived territory.
marking a stone as dead has the effect of converting dame/derived to known
for the region bounded by stones of the opposite color.
reanimating dead stones returns its adjacent empty nodes to dame.
alive stones adjacent to known territory can not be deanimated.

=head1 REPRESENTATION

Each category has a hash attribute in the scorable object.
they are divided into colors, where each color of that cat has a B::NodeSet.
the cats are named _alive, _dead, _known_terr, _derived_terr, _dame, maybe _seki later.
each transanimation initiates a floodfill to discover the boundry of its the region
bordered by the opposite color.

The dame category is an exception. there is no color specified.

=cut
