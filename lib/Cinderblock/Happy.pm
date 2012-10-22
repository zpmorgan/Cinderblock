package Cinderblock::Happy;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
my $json = Mojo::JSON->new();
#use Mojo::Redis;
use Cinderblock::Model;
use Time::HiRes;

# Websocket.
sub happychat{
   my $self = shift;
   my $ws = $self->tx;
   my $channel_name = $self->stash('channel');
   my $sub_redis = $self->model->sub_redis->timeout(15);
   $sub_redis->on(close => sub{say 'happy snghub_regdgis closing'});
   #$self->stash(hc_redis => $sub_redis);
   
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

   $sub_redis->subscribe($hc_channel_name, 'DONTDIEONME' => sub{
         my ($redis, $event) = @_;
         if ($event->[0] eq 'subscribe'){
            return;
         };
         return if ($event->[2] eq 'ping');
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
      my $time_ms = int(Time::HiRes::time() * 1000);
      my $speaker = $self->ident->{username};

      say "[$channel_name Message] $speaker: $msg";
      # push to a redis queue which stores last 100 msgs.
      # most recent first..
      my $happy_msg_out = {
         type => 'happy_msg',
         text => $text,
         time_ms => $time_ms,
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
   $self->on(finish => sub {
         my $ws = shift;
         #my $sub_redis = $self->stash('hc_sub_redis');
         #delete $self->stash->{hc_sub_redis};
         #$sub_redis->disconnect;
         $sub_redis->DESTROY;
         #$sub_redis->timeout(2);
         #$sub_redis->ioloop->remove($sub_redis->{_connection});
         say 'hc WebSocket closed.';
      });
}

1;
