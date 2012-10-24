package Test::Cinderblock::Game;
use Moose;

has 'ua' => (
   is => 'ro',
   isa=>'Mojo::UserAgent',
   default => sub{Test::Cinderblock->new('Cinderblock')->ua},
# Mojo::UserAgent->new(ioloop => Mojo::IOLoop->new())},
); # required=>1);

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
      $tx->on(message => sub{
            my ($tx,$msg) = @_;
            $self->{last_msg} = $msg;
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
   $self->ua->ioloop->start;
   return $self->{last_msg};
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


1;
