package Cinderblock::Game;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();

sub sessid{
   my $self = shift;
   my $sessid = $self->session('session_id');
   unless ($sessid){
      $sessid = $self->redis_block(incr => 'next_session_id');
      $self->session(session_id => $sessid);
   }
   return $sessid;
}

sub new_game{
   my $self = shift;
   my $game_id = $self->redis_block(incr => 'next_game_id');
   my $sessid = $self->sessid;
   my $newgame = {
      move_events => [],
      board => [],
   };
   $self->getset_redis->set("game:$game_id" => $json->encode($newgame));
   # assign player role to $self->session
   my $color = (rand>.5) ? 'b' : 'w';
   $self->getset_redis->hset("gameroles:$game_id", $color => $sessid);
   
   $self->redirect_to("/game/$game_id");
   $self->render(text => 'phoo');
}

sub do_game{
   my $self = shift;
   my $game_id = $self->stash('game_id');
   my %roles = %{$self->redis_block('HGETALL',"gameroles:$game_id")};
   my $sessid = $self->sessid;

   # what part does this session play? Watcher or player?
   $self->stash(my_role => 'watcher');
   for my $role_color(keys %roles){
      if($roles{$role_color} == $sessid){
         $self->stash(my_role => 'player');
         $self->stash(my_color => $role_color);
         last;
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
   
   my $sub_redis = Mojo::Redis->new(timeout => 20000);
   $sub_redis->protocol_redis("Protocol::Redis::XS");
   $sub_redis->timeout(180);
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
         my $board = $game->{board};
         my $move_attempt = $msg_data->{move_attempt};
         my $row = $move_attempt->{node}[0];
         my $col = $move_attempt->{node}[1];
         my $collision = $board->[$row][$col];
         if($collision){return}

         $game->{board}->[$row][$col] = $move_attempt->{stone};

         #my $move_events = $game->{move_events};
         my $new_event = {
            node => [$row,$col],
            stone => $move_attempt->{stone},
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

1;
