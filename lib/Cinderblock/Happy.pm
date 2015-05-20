package Cinderblock::Happy;
use Modern::Perl;;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json encode_json);
#use Mojo::Redis;
use Cinderblock::Model;
use Time::HiRes;
use Data::Dumper;

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
   
   # zfolk is a redis sorted set which tracks folk membership over time.

   my $folk = {
      ident_id => $self->ident->{id},
      ident_name => $self->ident->{username},
      channel_name => $channel_name,
      time => Time::HiRes::time(),
      fid => $self->redis_block(INCR => 'next_fid'),
   };
   my $folk_json = encode_json($folk);

   #TODO: use to cull unrenewed/expired folk membership?
   my $folk_bump = sub{
      $self->model->getset_redis->zadd( 
         zfolk => Time::HiRes::time(),
         $folk_json
      );
   };
   
   #do the folk list
   my $folk_enter_msg = {
      type => 'folk_enter',
      folk => $folk,
   };
   $self->pub_redis->publish($hc_channel_name, encode_json($folk_enter_msg));
   #put folk entry in some structure recording channel participation
   #a json-encoded list in a hash keyed by channel-name
   my $folk_list = decode_json($self->redis_block(
         HGET => "hfolk" => $hc_channel_name 
      ));
   push @$folk_list, $folk;
   $self->redis_block( 
      HSET => "hfolk" => $hc_channel_name, encode_json($folk_list)
   );
   # send current folk list to client.
   $ws->send( encode_json( {
            type => 'folk_list',
            folk_list => $folk_list,
   } ) );


   #subscribe to channel events: messages, pings, folk list updates.
   $sub_redis->subscribe($hc_channel_name, 'DONTDIEONME' => sub{
         my ($redis, $event) = @_;
         if ($event->[0] eq 'subscribe'){
            return;
         };
         return if ($event->[2] eq 'ping');
         say $event->[2];
         $ws->send($event->[2]);
      });
   $self->on(message => sub {
      my ($ws, $msg) = @_;
      my $msg_data = decode_json($msg);
      if($msg_data->{type} eq 'ping'){
         $ws->send(encode_json({type=>'pong'}));
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
      $happy_msg_out = encode_json($happy_msg_out);
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
         $sub_redis->DESTROY;
         say 'hc WebSocket closed.';

         #remove from folk list
         my $folk_leave_msg = {
            type => 'folk_leave',
            folk => $folk,
         };
         $folk_leave_msg = encode_json($folk_leave_msg);
         $self->model->pub_redis->publish( $hc_channel_name => $folk_leave_msg );
         my $folk_list = decode_json($self->redis_block(
               HGET => "hfolk" => $hc_channel_name 
            ) || '[]');
         # say join ',',sort map {$_->{fid}} @$folk_list;
         $folk_list = [ grep {$_->{fid} != $folk->{fid} } @$folk_list ];
         $self->redis_block( 
            HSET => "hfolk" => $hc_channel_name, encode_json($folk_list)
         );
      });
}

1;
