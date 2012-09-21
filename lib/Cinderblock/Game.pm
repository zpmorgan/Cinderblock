package Cinderblock::Game;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();

# This action will render a template
sub game_event_socket{
   my $self = shift;

   warn("Client Connect: ".$self->tx);
   my $ws = $self->tx;
   $ws->send(join '',1..30);

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
   Mojo::IOLoop->recurring(1 => sub{
         my $msg = {
            event_type => 'move',
            move => {
               row => int rand(19),
               col => int rand(19),
               stone => (rand>.5) ? 'b' : 'w',
            }
         };
         $ws->send($json->encode($msg));
      });
}

use Mojo::Redis;
# request made through websocket.
sub attempt_move{
   my ($self, $msg_data) = @_;
   my $redis = Mojo::Redis->new();

   $redis->get ('game:4' => sub{
         my ($redis,$game) = @_;
         my $board = $game->{board};
         my $move_attempt = $msg_data->{move_attempt};
         my $row = $move_attempt->{row};
         my $col = $move_attempt->{col};
         my $collision = $board->[$row][$col];
         if($collision){return}
         $board->[$row][$col] = $move_attempt->{stone};

         my $move_events = $game->{move_events};
         my $new_event = {
            node => [$row,$col],
            stone => $move_attempt->{stone},
         };
         push @{$move_events}, $new_event;
         $redis->set('game:4', $game => sub{$redis->quit});
         $self->publish_move_event($new_event);
      });
   $redis->get ('game:4' => 4);
   #$redis->ioloop->start;
   $redis->get ('game' => sub{$redis->quit; die @_});
}

sub publish_move_event{
   my ($self,$mov) = @_;
}

1;
