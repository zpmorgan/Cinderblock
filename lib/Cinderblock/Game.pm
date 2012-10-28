package Cinderblock::Game;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();
use Mojo::Redis;
use Data::Dumper;

use Games::Go::Cinderblock::Rulemap;
use Games::Go::Cinderblock::Rulemap::Rect;

use Cinderblock::Model;
use Time::HiRes;

sub cur_time_ms{
   return int(Time::HiRes::time() * 1000)
}

sub new_game_form{
   my $self = shift;
   $self->render(template => 'game/new_game_form');
}
sub welcome{
   my $self = shift;
   my @actives = $self->model->recently_active_games(1);
   $self->stash(last_active_game => $actives[0]);
   $self->render(template => 'game/welcome');
}
sub activity{ # show recently active games.
   my $self = shift;
   my @actives = $self->model->recently_active_games(50);
   $self->stash(recently_active_games => \@actives);
   $self->render(template => 'game/activity');
}

sub new_game{
   my $self = shift;
   my $w = int($self->param('w')) // 19;
   my $h = int($self->param('h')) // 19;
   if (($w<1) or ($w>30) or ($h<1) or ($h>30)){
      $self->stash(msg => 'height and width must be from 2 to 30'); 
      return $self->render(template => 'game/new_game_form');
   };
   my $wrap_v = $self->param('wrap_v') ? 1 : 0;
   my $wrap_h = $self->param('wrap_h') ? 1 : 0;

   my %roles; #initial roles. color => ident_id
   my $color = (rand > .5) ? 'w' : 'b';
   $roles{$color} = $self->ident->{id};
   if($self->param('play_against') eq 'self'){
      my $other_color = ($color eq 'b' ? 'w' : 'b');
      $roles{$other_color} = $self->ident->{id};
   }
   my $game = Cinderblock::Model::Game->new(
      h => $h, w => $w,
      wrap_v => $wrap_v, wrap_h => $wrap_h,
      roles => \%roles,
   );
   $self->redirect_to("/game/" . $game->id);
   return $self->render(text => 'phoo');
}

sub be_invited{
   my $self = shift;
   my $code = $self->stash('invite_code');
   my $invite = $self->model->invite($code);

   my $game_id = $invite->{game_id};
   my $game = $self->model->game($game_id);

   my $color = $invite->{color};
   my $current_role_ident = $self->model->game_role_ident( $game_id, $color);
   unless ($current_role_ident){
      $game->set_role( $color, $self->ident->{id});
   }
   $self->redirect_to("/game/$game_id");
   $self->render(text => '');
}

sub do_game{
   my $self = shift;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   unless($game){
      $self->stash(msg => "game $game_id not found.");
      return $self->render(template => 'game/welcome');
   }
   my %roles = %{$game->roles};
   my $sessid = $self->sessid;
   $self->stash(game => $game);

   # what part does this session play? Watcher or player?
   # $self->stash(my_role => 'watcher');
   my @my_colors;
   my $my_role = 'watcher';
   for my $role_color(keys %roles){
      if($roles{$role_color} == $self->ident->{id}){
         $my_role = 'player';
         push @my_colors, $role_color;
      }
   }
   my $b_ident = $self->model->game_role_ident($game_id, 'b') // {};
   my $w_ident = $self->model->game_role_ident($game_id, 'w') // {};
   $self->stash(b_ident => $b_ident);
   $self->stash(w_ident => $w_ident);
   $self->stash(my_role => $my_role);
   $self->stash(my_colors => \@my_colors);
   if( keys %roles == 1 ){ #currently only one player ?
      if ($self->stash('my_role') eq 'player'){
         #generate an invite code.
         my $other_color = ($self->stash('my_colors')->[0] eq'b') ?'w':'b';
         my $invitecode = int rand(2<<30);
         my $invite = {game_id => $game_id, color => $other_color};
         $self->getset_redis->hset(invite => $invitecode => $json->encode($invite));
         $self->stash(invite_code => $invitecode);
      }
   }
   $self->render(template => 'game/index');
}

sub game_event_socket{
   my $self = shift;
   my $game_id = $self->stash('game_id');
   say 'OPEN_GAME_SOCK ' . $game_id;
   my $ws = $self->tx;
   my $sub_redis = $self->model->sub_redis->timeout(15);
   $sub_redis->on(close => sub{say "GAM $game_id REDIS SUB IS CLOSIGN"});
   # push game events when they come down the tube.
   $sub_redis->subscribe('game_events:'.$game_id , 'DONTDIEONME' => sub{
         my ($redis, $event) = @_;
         if ($event->[0] eq 'subscribe'){
            return;
         }
         return if ($event->[2] eq 'ping');
         $ws->send($event->[2]);
      });
   my $game = $self->model->game($game_id);
   my $all_game_events = $game->game_events_ref;
   for my $e(@$all_game_events){
      $ws->send($json->encode($e));
   }
   if ($game->status eq 'scoring'){
      $ws->send( $json->encode( 
            $self->model->stordscor($game_id)->generate_a_scorable_event()
         ));
   }
   
   $self->on(message => sub {
         my ($ws, $msg) = @_;
         say "Message: $msg";
         my $msg_data = $json->decode($msg);
         my $action = $msg_data->{action};
         if($action eq 'attempt_move'){
            $self->attempt_move($msg_data);
         }
         elsif($action eq 'attempt_pass'){
            $self->attempt_pass($msg_data);
         }
         elsif($action eq 'attempt_resign'){
            $self->attempt_resign($msg_data);
         }
         elsif($action eq 'attempt_transanimate'){
            $self->attempt_transanimate($msg_data);
         }
         elsif($action eq 'attempt_done_scoring'){
            $self->attempt_done_scoring($msg_data);
         }
         elsif($action eq 'ping'){
            $ws->send('{"event_type":"pong"}');
         }
         # else pong?
      });
   $self->on(finish => sub {
         my $ws = shift;
         #$sub_redis->disconnect;
         #$sub_redis->ioloop->remove($sub_redis->{_connection});
         say 'Game WebSocket closed.';
         $sub_redis->DESTROY;
         return;
         #my @ids = ($sub_redis->{_connection}, keys %{$sub_redis->{_ids}});
         #for (@ids){
         #   $sub_redis->ioloop->remove($_);
         #}
         #delete $sub_redis->{_connection};
         #delete $sub_redis->{_ids};
      });
   my $event = {event_type => 'hello', hello=>'hello'};
   $ws->send($json->encode($event));
   Mojo::IOLoop->recurring(10 => sub{
         my $event = {event_type => 'ping', ping=>'ping'};
         $ws->send($json->encode($event));
      });
}

# for when a move attempt fails: 
# return $self->crap_out ($reason)
my %denial_reasons = (
   0 => 'Game not active.',
   1 => 'attempt color has no perogative',
   2 => 'there is no such role for that color/game combination.',
   3 => 'You do not have that color/game role. it is not yours.',
   4 => 'Move invalid..',
   5 => 'KO Collision.',
   6 => 'game not scoring.',
   7 => 'transanimation operation on an incorrect scorable.',
   88 => 'unimplemented something.',
);
sub crap_out{
   my ($self,$msg) = @_;
   my $ws = $self->tx;
   $msg = $msg . ': ' . ($denial_reasons{$msg} // 'FOO');
   my $denial = {
      type => 'denial',
      denial => $msg,
   };
   $ws->send($json->encode($denial));
}
use Carp::Always;
use Digest::MD5 qw(md5_base64);

# request made through websocket.
sub attempt_move{
   my ($self, $msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   #can move?
   my $move_attempt = $msg->{move_attempt};
   my $turn = $game->turn;
   my $color = $move_attempt->{color};
   $game->status ('active') if($game->status eq 'scoring');
   return $self->crap_out(0) unless $game->status eq 'active';
   return $self->crap_out(1) unless $color eq $turn;
   my $roles = $game->roles;
   my $turn_ident = $self->model->game_role_ident($game_id, $turn) // {};
   return $self->crap_out(2) unless (defined $turn_ident);
   return $self->crap_out(3) unless ($turn_ident->{id} == $self->ident->{id});
   # Can Move!
   # valid move?
   my %eval_result; #newboard, move_hash, delta,...
   {
      my $node = $move_attempt->{node};
      #my $w = $game->w;
      #my $h = $game->h;
      #my $rulemap = Basilisk::Rulemap::Rect->new(
      #my $rulemap = Games::Go::Cinderblock::Rulemap::Rect->new(
      #   h => $h, w => $w,
      #   wrap_v => $game->wrap_v,
      #   wrap_h => $game->wrap_h,
      #);
      my $rulemap = $game->rulemap;
      my $state = $game->state;
#      my $board = $game->board;
#      my $state = Games::Go::Cinderblock::State->new(
#         rulemap => $rulemap,
#         turn => $game->turn,
#         board => $board,
#         captures => $game->captures,
#      );
      #my ($newboard,$fail,$caps) =
      #$rulemap->evaluate_move($board, $node, $color);
      my $result = $state->attempt_move(
         color => $color,
         node => $node,);
      # $caps is just a list of nodes.
      if($result->failed){return $self->crap_out(4)}
      my $newboard = $result->resulting_state->board;
      # now normalize & hash the board, check for collisions, & later store hash in event..
      my $normalized_state = $color .':'. $rulemap->normalize_board_to_string($newboard);
      my $move_hash = md5_base64($normalized_state);
      my $ko_collision =   
         grep {$_->{move_hash} && ($_->{move_hash} eq $move_hash)} 
         @{$game->game_events_ref};
      if($ko_collision){return $self->crap_out(5)}

      %eval_result = (
         newboard => $newboard,
         move_hash => $move_hash,
         delta => $result->delta,
         #caps => scalar 0, # $result->caps
         #turn => ($stone eq 'w') ? 'b' : 'w',
      );
   }
   #if (scalar @$caps){
   #   $game_event->{captures}{$stone} = scalar @$caps;
   #}

   # Valid Move!
   if($eval_result{delta}->diff_captures){
      my $caps_delt = $eval_result{delta}->captures;
      for my $color(keys %$caps_delt){
         $game->captures($color => $caps_delt->{$color}{after});
      }
   }
   if($eval_result{delta}->diff_board){
      $game->board ($eval_result{newboard});
   }
   if($eval_result{delta}->diff_turn){
      $game->turn ($game->next_turn);
   }
   my $event = {
      type => 'move', 
      color => $color,
      time_ms => cur_time_ms(),
      delta => $eval_result{delta}->to_args,
      move_hash => $eval_result{move_hash},
      #these 2 things in delta now:
      #   captures => {$color => $eval_result{caps}},
      # turn_after => $game->turn,
   };
   $game->push_event($event);
   $game->update();
}
sub attempt_pass{
   my ($self,$msg) = @_;
   say $self;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   my $color = $msg->{pass_attempt}{color};
   my $turn = $game->turn;
   return $self->crap_out(0) unless $game->status eq 'active';
   return $self->crap_out(1) unless $color eq $turn;
   my $roles = $game->roles;
   my $turn_ident = $self->model->game_role_ident($game_id, $turn) // {};
   return $self->crap_out(2) unless (defined $turn_ident);
   return $self->crap_out(3) unless ($turn_ident->{id} == $self->ident->{id});
   # success!
   $game->turn ($game->next_turn);
   my $event = {
      type => 'pass', 
      color => $color,
      #turn_after => $game->turn,
      time_ms => cur_time_ms(),
      delta => {turn => {before => $color, after => $game->turn}},
   };

   my $do_initialize_scorable = 0;
   if($game->last_move_was_pass){
      $game->set_status_scoring;
      $event->{status_after} = 'scoring';
      # nobody's turn during scoring.
      # an empty string will do.
      $event->{delta}{turn}{after} = '';
      $do_initialize_scorable = 1;
   }
   $game->push_event($event);
   $game->update();

   $self->initialize_scorable if $do_initialize_scorable;

   return;
}
sub attempt_resign{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return unless $game->status =~ /scoring|active/;
   # my $turn = $game->turn;
   my $color = $msg->{resign_attempt}{color};
   # return unless $color eq $turn;
   #my $roles = $game->roles;
   return $self->crap_out(88) unless $color;
   my $relevant_ident = $self->model->game_role_ident($game_id, $color) // {};
   return unless (defined $relevant_ident);
   return unless ($relevant_ident->{id} == $self->ident->{id});
   # success!
   $game->turn('none');
   $game->status('finished');
   $game->winner(($color eq 'b') ? 'w' : 'b');
   my $event = {
      type => 'resign', 
      color => $color,
      #turn_after => 'none', 
      time_ms => cur_time_ms(),
      winner => $game->winner,
      status_after => 'finished',
      delta => {turn => {before => $color, after => ''}},
   };
   $game->push_event($event);
   $game->update();
}

# This means that the 2nd pass has proceeded 
# at the behest of whomever procured this very websocket
sub initialize_scorable {
   my $self = shift;
   my $game_id = $self->stash('game_id');
   #my $game = $self->model->game($game_id);
   my $stordscor = $self->model->stordscor($game_id);
   $stordscor->publish();
   return;
}

# sub attempt_toggle_stone_state{
sub attempt_transanimate{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return $self->crap_out(6) unless $game->status eq 'scoring';
   #return $self->crap_out(1) unless $color eq $turn;

   my $attempt = $msg->{transanimate_attempt};
   my $msg_parent_scorable_r_id = $attempt->{parent_scorable_r_id};
   die 'no paremt scor id.' unless defined $msg_parent_scorable_r_id;

   my $stordscor = $game->stordscor;
   #my $scorable = $stordscor->scorable;
   #$self->model->block_redis->watch($scorkey);
   #my $scorable_representation = $self->model->redis_block(GET => $scorkey);
   #$scorable_representation = $json->decode($scorable_representation);
   #unless ($scorable_representation->{parent_scorable_id} == $parent_scorable_id){
   unless ($msg_parent_scorable_r_id == $stordscor->r_id){
      return $self->crap_out(7);
   }
   # construct state & g::g::cb::scorable from what's in redis.
   #my $state = $game->state;

   #my $deads = $scorable->dead;
   #my $dead_ns = $state->rulemap->nodeset;
   #for my $known_deads (values %$deads){
   #   my $ns = $state->rulemap->nodeset(@$known_deads);
   #   $dead_ns = $dead_ns->union($ns);
   #}
   #my $scorable_object = $state->scorable;
   #$scorable_object->deanimate($dead_ns);
   $stordscor->transanimate($attempt->{node});
   $stordscor->update_and_publish;
   return;
}

sub attempt_done_scoring{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return $self->crap_out(6) unless $game->status eq 'scoring';

   my $stordscor = $game->stordscor;
   my $attempt = $msg->{done_scoring_attempt};
   my $msg_parent_scorable_r_id = $attempt->{parent_scorable_r_id};
   die 'no paremt scor id.' unless defined $msg_parent_scorable_r_id;
   unless ($msg_parent_scorable_r_id == $stordscor->r_id){
      return $self->crap_out(7);
   }
   $stordscor->ident_approves($self->ident);
   $stordscor->update_and_publish;
   if($stordscor->do_all_approve()){
      #all approve. someone won.
      $game->status('finished');
      # my $winner = $scorable->winner; #derp
      my $winner = 'b';
      $game->winner($winner);
      # finish event.
      my $event = {
         type => 'finish', 
         time_ms => cur_time_ms(),
         winner => $game->winner,
         status_after => 'finished',
         score_difference => 12.3456789,
         delta => {},
      };
      $game->push_event($event);
      $game->update();
   }
   #action: 'attempt_done_scoring',
   #done_scoring_attempt: {
   #   parent_scorable_r_id : this.getLatestScorable().r_id,
}

1;
