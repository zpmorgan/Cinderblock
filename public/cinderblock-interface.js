
// this shows stones & sometimes score elements
Class('PlayersWidget', {
   has: {
      div : {is: 'ro'},
      shownScorable: {is: 'rw', init: null},
   },
   methods: {
      showScore : function(scorable){
         this.shownScorable = scorable;
         var dead = {
            w : scorable.dead.w.length,
            b : scorable.dead.b.length, };
         var terr = {
            w : scorable.terr.w.length,
            b : scorable.terr.b.length, };
         $.each(['w','b'], function(){
            var color = this;
            var score_elem = $('div.score-'+color);
            score_elem.text('');
            score_elem.append(
               $('<span>').append('dead: -' + dead[color]) 
               );
            score_elem.append( $('<br />') );
            score_elem.append(
               $('<span>').append('terr: ' + terr[color]) 
               );
            score_elem.append( $('<br />') );
         });
      },
      showWinner : function(end_event){
         console.log(end_event);
         var result_div = $('<div class="FOO-left-panel-controls" />');
         var win_color= end_event.winner;
         var reason;
         if (end_event.type == 'resign'){
            reason = 'Resign';
         }else {
            reason = end_event.score_difference;
         }
         result_div.text(win_color.toUpperCase() + '+' + reason);
         result_div.css('font-weight', 'bold');
         this.div.prepend(result_div);
      },
   },
});


Class('GameControlsWidget', {
   has: {
      game: {is : 'ro' },
      passButton : {is : 'ro'},
      resignButton : {is : 'ro'},
      doneScoringButton : {is : 'ro'},
      undoButton : {is : 'ro'},
   },
   methods: {
      beginScoring: function(){
         $("div#scoring-controls").show();
         $("div#special-moves").hide();
      },
   },
   after: {
      // http://code.google.com/p/joose-js/wiki/MethodModifiers#after
      initialize : function(){
         var game = this.game;
         this.passButton = $('#pass-button');
         this.getPassButton().click(function(){
            game.attemptPass();
         });
         this.resignButton = $('#resign-button');
         this.getResignButton().click(function(){
            game.attemptResign();
         });
         //scoring:
         this.doneScoringButton = $('#done-scoring-button');
         this.getDoneScoringButton().click(function(){
            game.attemptDoneScoring();
         });
      },
   },
});

Class('TimeControlsWidget', {
   has: {view : {is : 'ro'}},
   methods: {},
});

$.fn.PlayersWidget = function(){
   var foo = new PlayersWidget({div : this});
   return foo;
};
