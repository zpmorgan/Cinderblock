package Cinderblock::Game;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();

use basilisk::Rulemap;
use basilisk::Rulemap::Rect;

# use Cinderblock::Model;

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
         #my $timeout = 10000;
         $self->getset_redis->hset(invite => $invitecode => $json->encode($invite));
         $self->stash(invite_code => $invitecode);
      }
   }
   $self->render(template => 'game/index');
}

# This action will render a template
sub game_event_socket{
   my $self = shift;
   my $game_id = $self->stash('game_id');
#   warn("Client Connect: ".$self->tx);
   my $ws = $self->tx;
   
   my $sub_redis = Mojo::Redis->new(timeout => 2*3600);
   $sub_redis->timeout(2*3600);
   $sub_redis->on(error => sub{
         my($redis, $error) = @_;
         warn "[sub_REDIS ERROR] $error\n";
      });
   $sub_redis->on(close => sub{
         my($redis, $error) = @_;
         warn "[sub_REDIS] CLOSE...\n";
      });
   #$sub_redis->protocol_redis("Protocol::Redis::XS");
   #$sub_redis->timeout(180000);
   $self->stash(sub_redis => $sub_redis);
   # push game events when they come down the tube.
   $sub_redis->subscribe('game_events:'.$game_id => sub{
         my ($redis, $event) = @_;
         return if $event->[0] eq 'subscribe';
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
      });
   $self->on(finish => sub {
         my $ws = shift;
         say 'WebSocket closed.';
      });
   Mojo::IOLoop->recurring(10 => sub{
         my $event = {event_type => 'hello', hello=>'hello'};
         $ws->send($json->encode($event));
      });
}

use Digest::MD5 qw(md5_base64);

# request made through websocket.
sub attempt_move{
   my ($self, $msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   #can move?
   my $move_attempt = $msg->{move_attempt};
   return unless $game->status eq 'active';
   my $turn = $game->turn;
   my $color = $move_attempt->{color};
   return unless $color eq $turn;
   my $roles = $game->roles;
   my $turn_ident = $self->model->game_role_ident($game_id, $turn) // {};
   return unless (defined $turn_ident);
   return unless ($turn_ident->{id} == $self->ident->{id});
   # Can Move!
   # valid move?
   my %eval_result; #newboard, move_hash, delta,...
   {
      my $row = $move_attempt->{node}[0];
      my $col = $move_attempt->{node}[1];
      my $w = $game->w;
      my $h = $game->h;
      my $node = [$row,$col];

      my $rulemap = basilisk::Rulemap::Rect->new(
         h => $h, w => $w,
         wrap_v => $game->wrap_v,
         wrap_h => $game->wrap_h,
      );
      my $board = $game->board;
      my ($newboard,$fail,$caps) =
      $rulemap->evaluate_move($board, $node, $color);
      # $caps is just a list of nodes.
      if($fail){return}
      # now normalize & hash the board, check for collisions, & later store hash in event..
      my $normalized_state = $color .':'. $rulemap->normalize_board_to_string($newboard);
      my $move_hash = md5_base64($normalized_state);
      my $ko_collision =   
         grep {$_->{move_hash} && ($_->{move_hash} eq $move_hash)} 
         @{$game->game_events_ref};
      if($ko_collision){return}

      %eval_result = (
         newboard => $newboard,
         #turn => ($stone eq 'w') ? 'b' : 'w',
         move_hash => $move_hash,
         delta => $rulemap->delta($board, $newboard),
         caps => scalar @$caps,
      );
   }
   #if (scalar @$caps){
   #   $game_event->{captures}{$stone} = scalar @$caps;
   #}

   # Valid Move!
   $game->board ($eval_result{newboard});
   $game->add_captures ($color, $eval_result{caps});
   $game->turn ($game->next_turn);
   my $event = {
      type => 'move', 
      color => $color,
      turn_after => $game->turn,
      time_ms => cur_time_ms(),
      captures => {$color => $eval_result{caps}},
      delta => $eval_result{delta},
      move_hash => $eval_result{move_hash},
   };
   $game->push_event($event);
   if($game->is_doubly_passed){
      #   $game->set_status_scoring;
   }
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
   $game->push_event($event);
   if($game->is_doubly_passed){
      #   $game->set_status_scoring;
   }
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
   };
   $game->push_event($event);
   $game->update();
}

sub attempt_toggle_stone_state{
   my ($self,$msg) = @_;
   my $game_id = $self->stash('game_id');
   my $game = $self->model->game($game_id);
   return unless $game->status eq 'scoring';

}
         
# Websocket.
sub happychat{
   my $self = shift;
   my $ws = $self->tx;
   my $channel_name = $self->stash('channel');
   my $sub_redis = $self->model->new_sub_redis();
   $self->stash(hc_redis => $sub_redis);
   
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
   $sub_redis->subscribe($hc_channel_name => sub{
         my ($redis, $event) = @_;
         return if $event->[0] eq 'subscribe';
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
}

# Websocket.
sub sadchat{
   my $self = shift;
   my $ws = $self->tx;
   my $sub_redis = $self->model->new_sub_redis;
   $self->stash(sub_redis => $sub_redis);

   $self->getset_redis->lrange('sadchat_messages', 0, 100, sub{
         my ($redis, $res) = @_;
         for my $m (reverse @$res){
            $self->pub_redis->publish('sadchat', $m);
         }
      });
   # push sad msg events when they come down the tube.
   $sub_redis->subscribe('sadchat' => sub{
         my ($redis, $event) = @_;
         return if $event->[0] eq 'subscribe';
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
         warn $text;
         return if length($text) > 400 or $text eq '';
         my $time_ms = cur_time_ms();
         my $speaker = $self->ident->{username};

         say "Message?: $msg";
         # push to a redis queue which stores last 100 msgs.
         # most recent first..
         my $sad_msg_out = {
            type => 'sad_msg',
            text => $text,
            time_ms => cur_time_ms(),
            speaker => $speaker,
         };
         $sad_msg_out = $json->encode($sad_msg_out);
         $self->getset_redis->lpush(sadchat_messages => $sad_msg_out);
         $self->getset_redis->ltrim(sadchat_messages => 0,99);
         $self->getset_redis->lpush(sadchat_messages_all => $sad_msg_out);#archive?
         $self->pub_redis->publish('sadchat', $sad_msg_out);
      });
}

1;
