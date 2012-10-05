package Cinderblock::Auth; # s/Auth/Ident/
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();

sub FOO_sessid{
   my $self = shift;
   my $sessid = $self->session('session_id');
   unless ($sessid){
      # new_session
      $sessid = $self->redis_block(incr => 'next_session_id');
      $self->session(session_id => $sessid);
   }
   return $sessid;
}

sub FOO_auth{
   my $self = shift;
   $self->render(template => 'auth/new_authsies');
}


use Cache::File;
use LWPx::ParanoidAgent;
use Net::OpenID::Consumer;
use Readonly;
use URI::Escape;


Readonly my $FOO_CONSUMER_SECRET => <<'EOQ';
Scissors cuts paper, paper covers rock, rock crushes lizard, lizard poisons Spock, Spock smashes scissors, scissors decapitates lizard, lizard eats paper, paper disproves Spock, Spock vaporizes rock, and as it always has, rock crushes scissors.
EOQ
Readonly my $CONSUMER_SECRET => <<'EOQ';
FOO rock cruxhes liwzard, lizardo Spoisons pock, FOO
EOQ
Readonly my $CACHE_ROOT => '/tmp/cache';

sub login {
   my $self = shift;
   $self->render(template => 'auth/login');
}

sub openid_login {
    my $self = shift;
    my $provider = $self->stash('oid_provider');

    my %id_urls = (
       google => 'https://www.google.com/accounts/o8/id',
       # facebook => 'https://facebook.com/openid/receiver.php',
       stackexchange => 'https://openid.stackexchange.com',
       yahoo => 'https://me.yahoo.com',
       myopenid => 'https://www.myopenid.com/',
    );
    my $id_url = $id_urls{lc $provider};
    die "provider $provider not found?" unless $id_url;

    my %params = @{ $self->req->params->params };

    my $my_url = $self->req->url->base;

    $self->app->log->debug(qq{MY URL[$my_url]});

    my $cache = Cache::File->new( cache_root => $CACHE_ROOT );
    my $csr = Net::OpenID::Consumer->new(
        ua              => LWPx::ParanoidAgent->new,
        cache           => $cache,
        args            => \%params,
        consumer_secret => $CONSUMER_SECRET,
        required_root   => $my_url
    );

    my $claimed_identity = $csr->claimed_identity($id_url);

    $claimed_identity->set_extension_args(
       'http://openid.net/extensions/sreg/1.1',
       {
          required => 'email',
          optional => 'fullname,nickname',
          # policy_url => 'http://example.com/privacypolicy.html',
       },
    );
    my $check_url = $claimed_identity->check_url(
        return_to      => qq{$my_url/openid_return},
        trust_root     => qq{$my_url/},
        delayed_return => 1,
    );

    $self->app->log->debug(qq{check_url[$check_url]});

    return $self->redirect_to($check_url);
};

sub openid_return {
    my $self = shift;

    my $my_url = $self->req->url->base;

    my %params = @{ $self->req->query_params->params };
    while ( my ( $k, $v ) = each %params ) {
        $params{$k} = URI::Escape::uri_unescape($v);
    }

    my $cache = Cache::File->new( cache_root => $CACHE_ROOT );
    my $csr = Net::OpenID::Consumer->new(
        ua              => LWPx::ParanoidAgent->new,
        cache           => $cache,
        args            => \%params,
        consumer_secret => $CONSUMER_SECRET,
        required_root   => $my_url
    );

    my $msg = q{NO response?};

    $csr->handle_server_response(
        not_openid => sub {
            die "Not an OpenID message";
        },
        setup_needed => sub {
            my $setup_url = shift;

            # Redirect the user to $setup_url
            $msg = qq{require setup [$setup_url]};

            $setup_url = URI::Escape::uri_unescape($setup_url);
            $self->app->log->debug(qq{setup_url[$setup_url]});

            $msg = q{};
            return $self->redirect_to($setup_url);
        },
        cancelled => sub {

            # Do something appropriate when the user hits "cancel" at the OP
            $msg = 'cancelled';
        },
        error => sub {
            my $err = shift;

            $self->app->log->error($err);

            die($err);
        },
        verified => sub {
            my $vident = shift;

            my $sreg = $vident->extension_fields(
               'http://openid.net/extensions/sreg/1.1',
            );
            # Do something with the VerifiedIdentity object $vident
            $msg = 'verified;<br />  display:' . $vident->display . "\n"
            . "<br /> url: " . $vident->url
            . "<br /> sreg: " . %$sreg;

            my $ident;
            my $ident_id = $self->redis_block(HGET => 'ident_id_by_url', $vident->url);
            if($ident_id) {
               # found existing identity.
               $self->session(ident_id => $ident_id);
               $ident = $self->redis_block(HGET => 'ident', $ident_id);
               $ident = $json->decode($ident);
               unless($ident){
                  $self->redis_block(HDEL => 'ident_id_by_url', $vident->url);
                  die;;
               }
               # return;
            }
            else {
               # create new identity:
               my $new_ident_id = $self->redis_block(INCR => 'next_ident_id');
               $self->redis_block(HSET => 'ident_id_by_url', $vident->url, $new_ident_id);
               $ident = {
                  username => 'user' . $new_ident_id,
                  id => $new_ident_id,
                  email => undef,
               };
               $self->redis_block(HSET => 'ident', $new_ident_id, $json->encode($ident));
            }
            # associate session with new|found identity
            $self->redis_block(HSET => 'session_ident', $self->sessid, $ident->{id});
            $self->session(ident_id => $ident->{id});
        },
    );
    $self->flash(msg => $msg);
    $self->redirect_to('/');
    $self->render( text => $msg ) if $msg ne q{};
};

sub logout{ 
   my $self = shift;
   $self->session(expires => 1);
   $self->redirect_to('/');
   $self->render_text('');
}

sub profile{ 
   my $self = shift;
   my $ident = $self->ident;
   unless($self->logged_in){
      return $self->render(template => 'auth/login', msg => 'not logged in..');
   }
   my @fields = qw/rank_self_estimate username/;
   if($self->req->method =~ /post/i){
      for(@fields){
         if(length($self->param($_)) > 50){
            return $self->render(template => 'auth/profile', msg=>'fish');
         }
         $ident->{$_} = $self->param($_);
      }
      $self->redis_block(HSET => 'ident', $ident->{id}, $json->encode($ident));
      $self->stash(msg => 'profile updated.');
   }
   $self->render(template => 'auth/profile');
}

1;

