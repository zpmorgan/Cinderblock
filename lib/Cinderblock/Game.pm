package Cinderblock::Game;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();

use basilisk::Rulemap;
use basilisk::Rulemap::Rect;

sub sessid{
   my $self = shift;
   my $sessid = $self->session('session_id');
   unless ($sessid){
      $sessid = $self->redis_block(incr => 'next_session_id');
      $self->session(session_id => $sessid);
   }
   return $sessid;
}

sub new_game_form{
   my $self = shift;
   $self->render(template => 'game/new_game_form');
}
sub welcome{
   my $self = shift;
   $self->render(template => 'game/welcome');
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
   my $sessid = $self->sessid;
   my $board = [ map{[map {''} 1..$w]} 1..$h ];
   my $newgame = {
      move_events => [],
      board => $board,
      w => $w,
      h => $h,
      wrap_v => $wrap_v,
      wrap_h => $wrap_h,
      turn => 'b',
   };
   $self->getset_redis->set("game:$game_id" => $json->encode($newgame));
   # assign player role to $self->session
   my $color = (rand>.5) ? 'b' : 'w';
   $self->set_game_player(game_id => $game_id, color => $color, sessid => $sessid);
   
   $self->redirect_to("/game/$game_id");
   $self->render(text => 'phoo');
}

# get or set $role
sub set_game_player{
   my $self = shift;
   my %opts = @_;
   my $sessid = $opts{sessid} // $self->sessid;
   my $gameid = $opts{game_id} // $self->stash('game_id');
   die unless $opts{color} =~ /^(b|w)$/;
   $self->redis_block(HSET => "gameroles:$gameid", $opts{color} => $sessid);
}
sub players_in_game{
   my $self = shift;
   my $game_id = shift;
   my $roles = $self->redis_block('HGETALL',"gameroles:$game_id");
   return $roles // {};
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
   $self->redis_block(HSET => "gameroles:$game_id", $invite->{color} => $self->sessid);

   $self->redirect_to("/game/$game_id");
   $self->render(text => '');
}

sub do_game{
   my $self = shift;
   my $game_id = $self->stash('game_id');
   my $roles = $self->players_in_game($game_id);
   die $roles unless ref($roles) eq 'HASH';
   my %roles = %$roles;
   my $sessid = $self->sessid;
   my $game_json = $self->redis_block(GET => "game:$game_id");
   my $game = $json->decode($game_json);
   $self->stash(game => $game);

   # what part does this session play? Watcher or player?
   $self->stash(my_role => 'watcher');
   for my $role_color(keys %roles){
      if($roles{$role_color} == $sessid){
         $self->stash(my_role => 'player');
         $self->stash(my_color => $role_color);
         last;
      }
   }
   if( keys %roles == 1 ){ #currently only one player ?
      if ($self->stash('my_role') eq 'player'){
         #generate an invite code.
         my $other_color = ($self->stash('my_color')eq'b') ?'w':'b';
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
   $self->getset_redis->get("game:$game_id" => sub{
         my ($redis,$res) = @_;
         my $game = $json->decode($res);
         my $all_move_events = $game->{move_events};
         for my $mv(@$all_move_events){
            my $event = {event_type => 'move', move=>$mv};
            $ws->send($json->encode($event));
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

# request made through websocket.
sub attempt_move{
   my ($self, $msg_data) = @_;
   my $game_id = $self->stash('game_id');
   my $redis1 = Mojo::Redis->new();
   $redis1->get ("game:$game_id" => sub{
         my ($redis,$game) = @_;
         $game = $json->decode($game);
         my $turn = $game->{turn};
         my $board = $game->{board};
         my ($w,$h) = @$game{qw/w h/};
         my $move_attempt = $msg_data->{move_attempt};
         my $stone = $move_attempt->{stone};
         unless ($stone eq $turn) {return}
         my $row = $move_attempt->{node}[0];
         my $col = $move_attempt->{node}[1];
   
         my $node = [$row,$col];
         my $rulemap = basilisk::Rulemap::Rect->new(
            h => $h, w => $w,
            wrap_v => $game->{wrap_v},
            wrap_h => $game->{wrap_h},
         );
         my ($newboard,$fail,$caps) =
            $rulemap->evaluate_move($board, $node, $stone);
            #my $collision = $board->[$row][$col];
         if($fail){return}
         my $delta = $rulemap->delta($board, $newboard);
         $game->{board} = $newboard;
         $game->{turn} = ($stone eq 'w') ? 'b' : 'w';

         #my $move_events = $game->{move_events};
         my $new_event = {
            node => [$row,$col],
            stone => $stone,
            delta => $delta,
            time => time,
            turn_after => $game->{turn},
         };
         push @{$game->{move_events}}, $new_event;

         $redis->set("game:$game_id", $json->encode($game) => sub{$redis1});
         $self->publish_move_event($new_event);
      });
}

sub publish_move_event{
   my ($self,$mov) = @_;
   my $event = {
      event_type => 'move',
      move => $mov,
   };
   $self->pub_redis->publish('game_events:'.$self->stash('game_id') => $json->encode($event));
}

sub sadchat{
   my $self = shift;
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
   # push sad msg events when they come down the tube.
   $sub_redis->subscribe('sadchat' => sub{
         my ($redis, $event) = @_;
         return if $event->[0] eq 'subscribe';
         $ws->send($event->[2]);
      });
   $self->on(message => sub {
         my ($ws, $msg) = @_;
         say "Message: $msg";
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
         my $out_msg = {text => $text};
         $self->pub_redis->publish('sadchat', $json->encode($out_msg));
         #$ws->send($json->encode($out_msg));
      });
}

1;
