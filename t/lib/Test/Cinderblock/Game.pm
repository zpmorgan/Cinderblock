package Test::Cinderblock::Game;
use 5.14.0;
use Moose;
use Mojo::JSON;
my $json = Mojo::JSON->new;

has test_cinderblock => (required => 1, is => 'ro', isa => 'Test::Cinderblock');

has 'ua' => (
   is => 'ro',
   isa=>'Mojo::UserAgent',
   default => sub{
      my $ua = $_[0]->test_cinderblock->ua;
      #my $ua = Test::Cinderblock->new('Cinderblock')->ua;
      $ua->cookie_jar ($_[0]->cookie_jar);
      return $ua;
   },
   lazy => 1,
);

has 'cookie_jar' => (isa=>'Mojo::UserAgent::CookieJar',is => 'ro',required=>1);

has 'id' => (isa=>'Int',is => 'ro',required=>1);

has 'ws_url' => (is=>'ro',isa=>'Str', lazy=>1, builder=>'_find_ws_url');

has 'sock' => (is => 'ro',isa=>'Mojo::Transaction::WebSocket',lazy=>1,builder=>'_opensock');

has game_page_url => (isa => 'Str', is => 'ro', required => 1);
has game_page_content => (isa => 'Str', is => 'ro', lazy => 1, builder => '_get_page');

sub _opensock{
   my $self = shift;
   # $self->ua->ioloop( Mojo::IOLoop->new() ); #block semi-independently?
   my $tx ;
   $self->ua->websocket($self->ws_url => sub{
      my $ua = shift;
      $tx = shift;
      #$tx->on(error => sub{die;});
      $tx->on(finish => sub{
            say @_;
         });
      $tx->on(message => sub{
            my ($tx,$msg) = @_;
            push @{$self->{msg_q}}, $msg;
            say $msg;
            $ua->ioloop->stop;
         });
      $ua->ioloop->stop;
   });
   $self->ua->ioloop->start;
   return $tx;
}

#return next message from game socket.
sub block_sock{
   my $self = shift;
   my $msg = shift @{$self->{msg_q}};
   return $msg if $msg;

   $self->sock;
   $self->ua->ioloop->start;
   $msg = shift @{$self->{msg_q}};
   $msg;
}
sub decoded_block_sock{
   my $self = shift;
   my $msg = $self->block_sock;
   return $json->decode($msg);
}

sub _get_page{
   my $self = shift;
   my $tx = $self->ua->get($self->game_page_url);
   $tx->res->body;
};
sub _find_ws_url{
   my $self = shift;
   $self->game_page_content =~ /ws_url:\s*"(.*)",\s*\n/;
   my $ws_url = $1;
   return $ws_url if $ws_url;
   warn 'ws_url not found!';
   warn $self->game_page_content;
   return 'TRY_SOME_SPOO';
};


sub do_move_attempt{
   my ($self, $color,$node) = @_;
   my $req = {
      action=>'attempt_move',
      move_attempt => {color => $color, node=>$node},
   };
   $self->sock->send( Mojo::JSON->encode($req) );
   return $req;
}

1;
