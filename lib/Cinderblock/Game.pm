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
   my $actives = $self->redis_block(ZREVRANGE => 'recently_actives_game_ids', 0,0);
   $self->stash(last_active_game => $actives->[0]);
   $self->render(template => 'game/welcome');
}
sub activity{ # show recently active games.
   my $self = shift;
   my $actives = $self->redis_block(ZREVRANGE => 'recently_actives_game_ids', -50,-1);
   $self->getset_redis(ZREMRANGE => 'recently_actives_game_ids', 0,-50);
   $self->stash(recently_active_games => $actives);
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

   my $game_id = $self->redis_block(incr => 'next_game_id');
   #my $sessid = $self->sessid;
   my $board = [ map{[map {''} 1..$w]} 1..$h ];
   my $newgame = {
      game_events => [],
      board => $board,
      w => $w,
      h => $h,
      wrap_v => $wrap_v,
      wrap_h => $wrap_h,
      turn => 'b',
   };
   $self->getset_redis->hset(game => $game_id => $json->encode($newgame));
   # assign player role to $self->session
   my $color = (rand>.5) ? 'b' : 'w';
   $self->model->set_game_player(game_id => $game_id, color => $color, sessid => $self->sessid);
   if($self->param('play_against') eq 'self'){
      my $other_color = ($color eq 'b' ? 'w' : 'b');
      $self->model->set_game_player(game_id => $game_id, color => $other_color, sessid => $self->sessid);
   }
   
   $self->redirect_to("/game/$game_id");
   $self->render(text => 'phoo');
}

sub players_in_game{
   my $self = shift;
   my $game_id = shift;
   my $roles = $self->redis_block('HGET',game_roles => $game_id) // '{}';
   return $json->decode($roles);
}

sub be_invited{
   my $self = shift;
   my $code = $self->stash('invite_code');
   my $key = "invite:$code";
   my @res = $self->redis_block(
      ['multi'],
      [get => $key],
      [del => $key],
      ['exec']
   );
   my ($invite, $del) = @{$res[3]};
   unless ($invite){
      return $self->render_text("invite code not found or already used.")
   }
   $invite = $json->decode($invite);
   my $game_id = $invite->{game_id};
   # $self->redis_block(HSET => "gameroles:$game_id", $invite->{color} => $self->sessid);
   $self->model->set_game_player(
      game_id => $game_id,
      color => $invite->{color},
      ident_id => $self->ident->{id},);

   $self->redirect_to("/game/$game_id");
   $self->render(text => '');
   #say 'invitee sessid '.$self->sessid;
   #say 'invitee ident id '.$self->ident->{id};
}

sub do_game{
   my $self = shift;
   my $game_id = $self->stash('game_id');
   my $roles = $self->players_in_game($game_id);
#   die $roles unless ref($roles) eq 'HASH';
   my %roles = %$roles;
   my $sessid = $self->sessid;
   my $game_json = $self->redis_block(HGET => game => $game_id);
   my $game = $json->decode($game_json);
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
         my $timeout = 10000;
         $self->getset_redis->setex("invite:$invitecode", $timeout
            => $json->encode($invite));
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
   $self->getset_redis->hget(game => $game_id => sub{
         my ($redis,$res) = @_;
         my $game = $json->decode($res);
         my $all_game_events = $game->{game_events};
         for my $e(@$all_game_events){
            #my $event = {event_type => 'move', move=>$mv};
            $ws->send($json->encode($e));
         }
      });
   
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
   my $roles = $self->players_in_game($game_id);
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
         wrap_v => $game->{wrap_v},
         wrap_h => $game->{wrap_h},
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

      #my $delta = $rulemap->delta($board, $newboard);
      #$game->{board} = $newboard;
      #$game->{turn} = ($stone eq 'w') ? 'b' : 'w';
      %eval_result = (
         newboard => $newboard,
         #turn => ($stone eq 'w') ? 'b' : 'w',
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
   my $roles = $self->players_in_game($game_id);
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
   my $roles = $self->players_in_game($game_id);
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
   my $game = $self->model->redis_block(hget => game => $game_id);
   $game = $json->decode($game);

   my $status = $game->{status} // 'active';
   return unless $game->{status} eq 'scoring';
}
         
# after pass,pass
sub launch_score_mode{
   die;
   my $self = shift;
   my $game = $self->model->game('id');
   $game->adjust_state(status => 'scoring');
   $game->update();
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
