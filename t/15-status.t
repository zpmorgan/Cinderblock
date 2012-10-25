use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use FindBin '$Bin';
use lib "$Bin/lib";
use Test::Cinderblock;

my $t = Test::Cinderblock->new('Cinderblock');
my $app = $t->app;

my $tgame = $t->newgame();

my $board_6x6_scorable = [
   [qw[ 0 w 0 0 b b ]],
   [qw[ b w w b b w ]],
   [qw[ 0 b w b b w ]],
   [qw[ b w w b 0 0 ]],
   [qw[ w 0 w b b w ]],
   [qw[ w 0 w b w 0 ]],
];
#die %{$t->app->model->game($tgame->id)->data};
my $mgame = $t->app->model->game($tgame->id);
$mgame->board($board_6x6_scorable);
$mgame->update;

$tgame->do_pass_attempt('b');
$tgame->do_pass_attempt('w');

my $hello = $tgame->block_sock;

#first test: 
like($hello, qr/hello/, 'howdies!');

say 'EXPECTING MESSAGES BACK.';

my @res = map {$tgame->decoded_block_sock} 1..2;
is_deeply($res[0]->{delta}, {turn=>{before=>'b',after=>'w'}},
   'singlepass delta');
is_deeply($res[1]->{delta}, {turn=>{before=>'w',after=>''}},
   'doublepass delta: no turn after.');
is($res[0]->{status_after}, undef, 'no status_after in 1st res.');
is($res[1]->{status_after}, 'scoring', 'scoring status_after in 2nd res.');
{
   my $scorable_msg = $tgame->decoded_block_sock;
   my @expected_dame = ( [0,2],[0,3], [0,0],[3,4],[3,5] );
   my @expected_w_terr = ( [4,1],[5,1],[5,5] );
   my @expected_b_terr = ( [2,0] );
   my @expected_b_dead = (  );
   my @expected_w_dead = (  );

   is($scorable_msg->{type}, 'scorable', 'scorable msg has type scorable...');
   my $scorable = $scorable_msg->{scorable};
   my @dame = @{$scorable->{dame}};
   my @w_terr = @{$scorable->{terr}{w}};
   my @b_terr = @{$scorable->{terr}{b}};
   my @w_dead = @{$scorable->{dead}{w}};
   my @b_dead = @{$scorable->{dead}{b}};

   sub sort_nodes{
      my @nodes = @_;
      return sort { 
         $a->[0] <=> $b->[0] || # the result is -1,0,1 ...
         $a->[1] <=> $b->[1]    # so [1] when [0] is same
      } @nodes;
   }
   use Data::Dumper;
   sub cmp_node_lists{
      is_deeply(
         [sort_nodes @{$_[0]}], 
         [sort_nodes @{$_[1]}], 
         $_[2],
      );
   }

   cmp_node_lists(\@dame, \@expected_dame, 'initial dame: all stones alive.');
   cmp_node_lists(\@b_dead, \@expected_b_dead, 'initial b dead: all stones alive.');
   cmp_node_lists(\@w_dead, \@expected_w_dead, 'initial w dead: all stones alive.');
   cmp_node_lists(\@b_terr, \@expected_b_terr, 'initial b terr: all terr derived.');
   cmp_node_lists(\@w_terr, \@expected_w_terr, 'initial w terr: all terr derived.');
}
{
   $tgame->do_transanimate_attempt ([1,0]);
   #my $scorable = $game->decoded_block_sock;
   $tgame->expect_scorable(
      dame => [[0,2],[0,3],[3,4],[3,5]],
      terr => {
         w => [ [4,1],[5,1],[5,5], [0,0],[2,0] ],
         b => [],
      },
      dead => {
         w => [],
         b => [ [1,0],[2,1],[3,0] ],
      },
   );
   my @expected_dame = ( [0,2],[0,3], [0,0],[3,4],[3,5] );
   my @expected_w_terr = ( [4,1],[5,1],[5,5] );
   my @expected_b_terr = ( [2,0] );
   my @expected_b_dead = (  );
   my @expected_w_dead = (  );

}
      done_testing;





