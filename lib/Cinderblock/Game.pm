package Cinderblock::Game;
use common::sense;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();
use Mojo::Redis;

use Protocol::Redis::XS;

# This action will render a template
sub game_event_socket{
   my $self = shift;

#   warn("Client Connect: ".$self->tx);
   my $ws = $self->tx;
   $ws->send('hello');
   
   my $pubsub = Mojo::Redis->new;
   $pubsub->protocol_redis("Protocol::Redis::XS");
   $pubsub->timeout(180);
   $self->stash(pubsub_redis => $pubsub);
   # push game events when they come down the tube.
   $pubsub->subscribe('g' => sub{
         my ($redis, $event) = @_;
         return if $event->[0] eq 'subscribe';
         $ws->send($event->[2]);
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
         $ws->send('hello');
      });
}

# request made through websocket.
sub attempt_move{
   my ($self, $msg_data) = @_;
   my $redis1 = Mojo::Redis->new();
   $redis1->get ('game:4' => sub{
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

         $redis->set('game:4', $json->encode($game) => sub{$redis1});
         $redis->set('game', $$, sub{$redis1});
         $self->publish_move_event($new_event);
      });
}

sub publish_move_event{
   my ($self,$mov) = @_;
   my $pubsub = $self->stash('pubsub_redis');
   $pubsub->publish('g' => $json->encode($mov));
}

1;
