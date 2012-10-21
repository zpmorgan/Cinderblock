package Cinderblock::Game;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();
use Mojo::Redis;

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
   # push game events when they come down the tube.
   $sub_redis->subscribe('game_events:'.$game_id , 'DONTDIEONME' => sub{
         my ($redis, $event) = @_;
         if ($event->[0] eq 'subscribe'){
            #Scalar::Util::weaken($redis);
            #$self->stash(game_sub_redis => $sub_redis);
            #$redis->on(close => sub{say $redis . 'game_alfjd closing'});
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
         elsif($action eq 'attempt_toggle'){
            $self->attempt_toggle_stone_state($msg_data);
         }
         elsif($action eq 'ping'){
            $ws->send('{"event_type":"pong"}');
         }
         # else pong?
      });
   $self->on(finish => sub {
         my $ws = shift;
         #my $sub_redis = $self->stash('game_sub_redis');
         #delete $self->stash->{game_sub_redis};
         $sub_redis->disconnect;
         #$sub_redis->timeout(2);
         #$sub_redis->ioloop->remove($sub_redis->{_connection});
         say 'Game WebSocket closed.';
      });
   my $event = {event_type => 'hello', hello=>'hello'};
   $ws->send($json->encode($event));
   Mojo::IOLoop->recurring(10 => sub{
         my $event = {event_type => 'ping', ping=>'ping'};
         $ws->send($json->encode($event));
      });
}

use Digest::MD5 qw(md5_base64);

# for when a move attempt fails: 
# return $self->crap_out ($reason)
sub crap_out{
   my ($self,$msg) = @_;
   my $ws = $self->tx;
   my $denial = {
      type => 'denial',
      denial => $msg,
   };
   $ws->send($json->encode($denial));
}
use Carp::Always;

# request made through websocket.
sub attempt_move{
   my ($self, $msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   #can move?
   my $move_attempt = $msg->{move_attempt};
   my $turn = $game->turn;
   my $color = $move_attempt->{color};
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
      my $row = $move_attempt->{node}[0];
      my $col = $move_attempt->{node}[1];
      my $w = $game->w;
      my $h = $game->h;
      my $node = [$row,$col];

      #my $rulemap = Basilisk::Rulemap::Rect->new(
      my $rulemap = Games::Go::Cinderblock::Rulemap::Rect->new(
         h => $h, w => $w,
         wrap_v => $game->wrap_v,
         wrap_h => $game->wrap_h,
      );
      my $board = $game->board;
      my $state = Games::Go::Cinderblock::State->new(
         rulemap => $rulemap,
         turn => $game->turn,
         board => $board,
      );
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
      $game->add_captures ($color, $eval_result{caps});
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
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return unless $game->status eq 'active';
   my $turn = $game->turn;
   my $color = $msg->{pass_attempt}{color};
   return unless $color eq $turn;
   my $roles = $game->roles;
   my $turn_ident = $self->model->game_role_ident($game_id, $turn) // {};
   return unless (defined $turn_ident);
   return unless ($turn_ident->{id} == $self->ident->{id});
   # success!
   $game->turn ($game->next_turn);
   my $event = {
      type => 'pass', 
      color => $color,
      turn_after => $game->turn,
      time_ms => cur_time_ms(),
   };
   if($game->is_doubly_passed){
      $game->set_status_scoring;
      $event->{status_after} = 'scoring';
   }
   $game->push_event($event);
   $game->update();
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
      turn_after => 'none', 
      time_ms => cur_time_ms(),
      winner => $game->winner,
      status_after => 'finished',
   };
   $game->push_event($event);
   $game->update();
}

# sub attempt_toggle_stone_state{
sub scoring_operation{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return unless $game->status eq 'scoring';
   return unless $game->roles_of_ident_id ($self->ident->{id});
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
         
# Websocket.
sub happychat{
   my $self = shift;
   my $ws = $self->tx;
   my $channel_name = $self->stash('channel');
   my $sub_redis = $self->model->sub_redis->timeout(15);
   $sub_redis->on(close => sub{say 'happy snghub_regdgis closing'});
   #$self->stash(hc_redis => $sub_redis);
   
   # push sad msg events when they come down the tube.
   # put into a redis list:
   my $channel_store_name = "hc:$channel_name";
   #publish in a channel:
   my $hc_channel_name = 'happychat_'.$channel_name ;
   $self->getset_redis->lrange($channel_store_name , 0,-1, sub{
         my ($redis,$msgs) = @_;
         for my $m (@$msgs){
            $ws->send($m);
         }
   });

   $sub_redis->subscribe($hc_channel_name, 'DONTDIEONME' => sub{
         my ($redis, $event) = @_;
         if ($event->[0] eq 'subscribe'){
            #$redis->on(close => sub{say 'happy snghub_regdgis closing'});
            #$self->stash(hc_sub_redis => $redis);
            return;
         };
         return if ($event->[2] eq 'ping');
         $ws->send($event->[2]);
      });
   $self->on(message => sub {
      my ($ws, $msg) = @_;
      my $msg_data = $json->decode($msg);
      if($msg_data->{type} eq 'ping'){
         $ws->send($json->encode({type=>'pong'}));
         return;
      }
      if($msg_data->{type} eq 'pong'){
         return;
      }

      # not ping, not pong. so text...
      my $text = $msg_data->{text};
      return if length($text) > 400 or $text eq '';
      my $time_ms = cur_time_ms();
      my $speaker = $self->ident->{username};

      say "[$channel_name Message] $speaker: $msg";
      # push to a redis queue which stores last 100 msgs.
      # most recent first..
      my $happy_msg_out = {
         type => 'happy_msg',
         text => $text,
         time_ms => cur_time_ms(),
         speaker => $speaker,
      };
      $happy_msg_out = $json->encode($happy_msg_out);
      $self->pub_redis->publish($hc_channel_name, $happy_msg_out);
      $self->getset_redis->rpush($channel_store_name => $happy_msg_out);
      my $do_trim = ($channel_name =~ /welcome/) ? 1 : 0;
      if($do_trim){
         $self->getset_redis->ltrim($channel_store_name => -99,-1);
         $self->getset_redis->rpush("archive:$channel_store_name" => $happy_msg_out);#archive?
      }
   });
   $self->on(finish => sub {
         my $ws = shift;
         #my $sub_redis = $self->stash('hc_sub_redis');
         #delete $self->stash->{hc_sub_redis};
         $sub_redis->disconnect;
         #$sub_redis->timeout(2);
         #$sub_redis->ioloop->remove($sub_redis->{_connection});
         say 'hc WebSocket closed.';
      });
}


1;
