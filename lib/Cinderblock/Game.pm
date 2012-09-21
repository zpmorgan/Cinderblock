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

1;
