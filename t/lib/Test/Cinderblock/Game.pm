package Test::Cinderblock::Game;
use 5.14.0;
use Moose;
use Mojo::JSON;
my $json = Mojo::JSON->new;
use Test::More;
use Data::Dumper;

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
            say "@_" . 'FIIIIIIN';
            $self->{sock_finished} = 1;
            push @{$self->{msg_q}}, qw'fin fin fin' ;
         });
      $tx->on(message => sub{
            my ($tx,$msg) = @_;
            push @{$self->{msg_q}}, $msg;
            say $msg . '  Gumby';
            #$ua->ioloop->stop;
         });
      #$ua->ioloop->stop;
   });
   $self->ua->ioloop->one_tick while !$tx;
   #$self->ua->ioloop->start;
   return $tx;
}

#return next message from game socket.
sub block_sock{
   my $self = shift;
   $self->sock;
   die 'websocket closed..' if $self->{sock_finished};

   $self->{msg_q} //= [];

   while (!@{$self->{msg_q}}){
      $self->ua->ioloop->one_tick 
   }
   my $msg = shift @{$self->{msg_q}};
   return $msg;

   #$self->ua->ioloop->start;
   #$msg = shift @{$self->{msg_q}};
   #$msg;
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

sub do_pass_attempt{
   my ($self, $color) = @_;
   my $req = {
      action=>'attempt_pass',
      pass_attempt => {color => $color},
   };
   $self->sock->send( Mojo::JSON->encode($req) );
   return $req;
}

sub do_move_attempt{
   my ($self, $color,$node) = @_;
   my $req = {
      action=>'attempt_move',
      move_attempt => {color => $color, node=>$node},
   };
   $self->sock->send( Mojo::JSON->encode($req) );
   return $req;
}

sub do_transanimate_attempt{
   my ($self, $scorable_id, $node) = @_;
   my $req = {
      action=>'attempt_transanimate',
      transanimate_attempt => {node => $node, on_scorable => $scorable_id},
   };
   $self->sock->send( Mojo::JSON->encode($req) );
   return $req;
}

sub expect_scorable{
   my $self = shift;
   my %expect = @_;
   my $differ = 0;
   
   my $scorable_msg = $self->decoded_block_sock;
   my $scorable = $scorable->{scorable};

   $differ++ unless
      is_deeply($scorable->{dame}, $expect{dame}, 'expected dame');
   $differ++ unless
      is_deeply($scorable->{terr}{w}, $expect{terr}{w}, 'expected w terr');
   $differ++ unless
      is_deeply($scorable->{terr}{b}, $expect{terr}{b}, 'expected b terr');
   $differ++ unless
      is_deeply($scorable->{dead}{w}, $expect{dead}{w}, 'expected w dead');
   $differ++ unless
      is_deeply($scorable->{dead}{b}, $expect{dead}{b}, 'expected b dead');

   if($differ){
      diag('GOT' . Dumper($scorable));
      diag('expected' . Dumper(\%expect));
      $differ = 0;
   }
}



1;
