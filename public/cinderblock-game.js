'use strict';

// Goal:
// So Game has a View, game & view each have GridBoards.
// view has decoration & canvases...
// game has no reference to view... only callbacks?
//
// 'Scorable' territory does not include nodes with dead stones.
// maybe it should be more nuanced or something
// so just add that to terr for 2player, i guess.


// 2 utility funcs:
// modulus, doesn't mess up negatives.
function moddd(i, i_max) {
      return ((i % i_max) + i_max) % i_max;
}
// cross-platform mouse event, relative coords to target element(canvas,etc)
function mouseEventToRelative(e) {
    //this section is from http://www.quirksmode.org/js/events_properties.html
    var targ;
    if (!e)
        e = window.event;
    if (e.target)
        targ = e.target;
    else if (e.srcElement)
        targ = e.srcElement;
    if (targ.nodeType == 3) // defeat Safari bug
        targ = targ.parentNode;

    // jQuery normalizes the pageX and pageY
    // pageX,Y are the mouse positions relative to the document
    // offset() returns the position of the element relative to the document
    var x = e.pageX - $(targ).offset().left;
    var y = e.pageY - $(targ).offset().top;

    //return {"x": x, "y": y};
    return [x,y];
};

Class( "Board",{
   methods : {
      applyBoardDelta : function(boardDelta){
         var board = this;
         if(boardDelta.add != null){
            $.each(boardDelta.add, function(color,nodes){
               $.each(nodes, function(){
                  var node = this;
                  board.setNode(node, color);
               });
            });
         }
         if(boardDelta.remove != null){
            $.each(boardDelta.remove, function(color,nodes){
               $.each(nodes, function(){
                  var node = this;
                  board.clearNode(node);
               });
            });
         }
      },
   },

});

Class( "GraphBoard", {
   isa : Board,
   has : {
      n : {is : 'ro', required : true },
      data : {is : 'ro', required : false, 
         init:function(){
            return [];
         },
      },
   },
   methods : {
      getStoneAtNode : function(node){
         return this.getData()[node];
      },
      setNode : function(node,stone){
         this.getData()[node] = stone;
      },
      clearNode : function(node){
         this.getData()[node] = '';
      },
   },
});

Class( 'GridBoard', {
   isa : Board,
   has: {
      w: {is: 'ro', required: true},
      h: {is: 'ro', required: true},
      data: {
         is: 'ro', required: false, lazy : true,
         init: function(){ 
            var grid = [];
            for(var i=0; i<this.h; i++){
               grid.push([]);
            }
            return grid;
         },
      },
   },
   methods: {
      getStoneAtNode : function(node){
         return this.getData()[node[0]][node[1]];
      },
      setNode : function(node,stone){
         this.getData()[node[0]][node[1]] = stone;
      },
      clearNode : function(node){
         this.getData()[node[0]][node[1]] = '';
      },
   },
});

Role("Emitter", {
   has : {
      callbacks : {
         is : rw,
         init : {blargles : [function(){}]}
      },
   },
   methods : {
      on: function(signal, cb){
         var emitter = this;
         if(this.callbacks[signal] == null){
            this.callbacks[signal] = [];
         }
         this.callbacks[signal].push(
            $.proxy (cb, emitter));
      },
      emit : function(signal, args){
         if(this.callbacks[signal] == null){ return }
         $.each(this.callbacks[signal], function(){
            if(args){
               this.apply('fakescope', args);
            }
            else
               this();
         });
      },
   },
})
/* 
 * signals:
 * scorable_change
 * game_end
 * new_game_event
 */

Class('CinderblockGame', {
   does: [Emitter],
   has: {
     // empty_board_image_data: {is: 'rw'},
      // only stones: 
      // canvases went to view.
      //intermediateCanvas : {is:rw},
      // marked & scrolled.
      //finalCanvas : {is: rw},
      // rules:
      w : {is:'rw',init:19},
      h : {is:'rw',init:19},
      wrap_v : {is:'rw',init:false},
      wrap_h : {is:'rw',init:false},
      // game data:
      game_events :{is:'ro',init:function(){return []}},
      actual_board : {
         is: 'ro',  lazy:true, 
         isa: function () { return m.GridBoard },
         init:function () { return new GridBoard({w: this.w, h: this.h}) },
      },
      actual_turn : {is:'rw',init:'b'},
      latestScorable: {is: 'rw' }, //init:"active"},
      asstatus : {is: 'rw', init:"active"},
   },
   methods: {
      // TODO: numTurns?

      log : function(m){
         $('.sock-event-box').prepend(m + '<br />');
      },
      setupViewOnCanvas : function(cnvs){
         var view = new CinderblockView({
            game: this,
         });
         view.finagleCanvas(cnvs);
         this.on('scorable_change', function(){
            view.handleScorableChange();
         });
         return view;
      },

      handleMoveEvent : function(move_event){
         this.game_events.push(move_event);
         this.getActual_board().applyBoardDelta(move_event.delta.board);
         this.actual_turn = move_event.delta.turn.after;
         this.emit('new_game_event', [move_event]);
      },
      handlePassEvent : function(pe){
         this.game_events.push(pe);
         var delta = pe.delta;
         if(delta && delta.turn){
            this.actual_turn = delta.turn.after;
         }
         this.emit('new_game_event', [pe]);
      },
      handleResignEvent : function(re){
         this.game_events.push(re);
         //this.actual_turn = re.turn_after;
         this.emit('new_game_event', [re]);
         this.emit('game_end', [re]);
      },
      handleScorableMessage: function(msg){
         this.log('received scorable. showing scorable?');
         this.setLatestScorable(msg.scorable);
         this.emit('scorable_change') ;
      },
      handleFinishMessage : function(msg){
         this.game_events.push(msg); //okay?
         this.emit('new_game_event', [msg]);
         this.emit('game_end', [msg]);
      },

      changeAsstatus: function(newAsstatus){
         // active|scoring|finished
         if(newAsstatus == 'active'){
            this.setStatusActive(); 
            this.actual_turn = re.turn_after;
         }
         else if(newAsstatus == 'scoring'){
            this.setStatusScoring(); 
            this.actual_turn = null;
         }
         else if(newAsstatus == 'finished'){
            this.setStatusFinished(); 
            this.actual_turn = null;
         }
         this.emit('asstatus_changed', [newAsstatus]);
      },
      setStatusFinished: function(){
         this.setAsstatus('finished');
      },
      setStatusActive: function(){
      
      },
      setStatusScoring: function(){
         this.setAsstatus('scoring');
      },
   
      // no more funky callback things.

      openSocket : function(){
         var game = this;
      //   ws://127.0.0.1:3000/game/
         this.sock = new WebSocket(PORTAL_DATA.ws_url);

         this.sock.onmessage = function  (event) {
            game.log('msg: '+event.data);
            var msg = $.parseJSON(event.data);
            //
            if(msg.type == 'move'){
               game.handleMoveEvent(msg);
            }
            else if(msg.type == 'pass'){
               game.handlePassEvent(msg);
            }
            else if(msg.type == 'resign'){
               game.handleResignEvent(msg);
            }
            else if(msg.type == 'scorable'){
               game.handleScorableMessage(msg);
            }
            else if(msg.type == 'finish'){
               game.handleFinishMessage(msg);
            }
            //else if (msg.type == 'status_change'){
            //   game.handleStatusChange(msg);
            //}
            else if (msg.type == 'ping'){
               game.sock.send(JSON.stringify({action:'pong'}));
            }
            if(msg.status_after){
               game.log('setting asstatus: ' + msg.status_after);
               game.changeAsstatus(msg.status_after);
            }
         };
         this.sock.onopen = function () {
            game.log('Socket open');
            if(!game.time_initialized){
               game.time_initialized = Date.now();
            }
         };
         this.sock.onclose = function () {
            game.log('Socket close');
         };
      },

      // attempts don't return responses, they just send signals upwards
      attemptMove : function(node){
         var stone_collision = this.getActual_board().getStoneAtNode(node);
         if(stone_collision)
            return 0;
         var attempt = {
            action: 'attempt_move',
            move_attempt: {
               "node" : node,
               "color": this.actual_turn,
            }
         };
         this.sock.send(JSON.stringify(attempt));
      },
      attemptPass : function(){
         var attempt = {
            action: 'attempt_pass',
            pass_attempt: {
               "color": this.actual_turn,
            }
         };
         console.log(attempt);
         this.sock.send(JSON.stringify(attempt));
      },
      attemptResign : function(node){
         var attempt = {
            action: 'attempt_resign',
            resign_attempt: {
               "color": this.actual_turn,
            }
         };
         this.sock.send(JSON.stringify(attempt));
      },
      attemptTransanimate: function(node){
         this.log('ATTEMPTing TransAnimation');
         var attempt = {
            action: 'attempt_transanimate',
            transanimate_attempt: {
               parent_scorable_r_id : this.getLatestScorable().r_id,
               "node" : node,
            }
         };
         this.sock.send(JSON.stringify(attempt));
      },
      attemptDoneScoring : function(){
         this.log('ATTEMPTing scoring finish');
         var attempt = {
            action: 'attempt_done_scoring',
            done_scoring_attempt: {
               parent_scorable_r_id : this.getLatestScorable().r_id,
            }
         };
         this.sock.send(JSON.stringify(attempt));
      },
      timeSinceInitializedInMs : function(){
         if(!this.time_initialized)
            return -1;
         return Date.now() - this.time_initialized ;
      },
   },
}); //end CinderblockGame class



/*
 * signals:
 * virtual_move_change
 * captures_change
 */

Class ('CinderblockView', {
   does: [Emitter],
   has: {
      game: {
         isa: function () { return m.CinderblockGame} , 
         is:'ro',
      }, 
      finalCanvas : {is:'rw'},// required:true},
      intermediateCanvas: {is:'rw'},
      extra_w_stones_acquired: {is:'rw',init:false},
      // cached offsets for drawing:
      h_lines : {is:'ro',init:function(){return []}},
      v_lines : {is:'ro',init:function(){return []}},
      // TODO:to 'view'
      //this.virtual_board = new GridBoard({w: this.game.w, h: this.game.h});
      virtualMoveNum: {is:'rw',init:0},
      virtualBoard: {
         is:'ro',
         isa: function () { return m.GridBoard },
         init:function () { return new GridBoard({w: this.game.w, h: this.game.h}) },
      },
      virtualCaptures: {is:'ro',init: {w:0,b:0}},
      canvasFinagled : {is:'rw', required:false},
      //onVirtualMoveChange : function(move_num){},
      //onCapturesChange : function(color, new_val){},
      state : {is : 'rw', init : 'void'},
   },
   methods: {
      canvasWidth:  function(){return this.getFinalCanvas().width},
      canvasHeight: function(){return this.getFinalCanvas().height},


      can_toggle_chain_state: function() {return false;}, //what
      can_move : function(){
         if(PORTAL_DATA.role == 'watcher')
            return 0;
         if(! this.viewIsCurrent()) //this.virtualMoveNum != this.game.game_events.length)
            return 0;
         var turn = this.game.actual_turn;
         var can_move = 0;
         $.each(PORTAL_DATA.colors, function(){
            if (this == turn)
               can_move = 1;
         }); 
         return can_move;
      },


      drawLines : function(){
         var view= this;
         var ctx = this.getIntermediateCanvas().getContext('2d');
         var fctx = this.getFinalCanvas().getContext('2d');
         var margin = this.margin;
         var grid_box = this.grid_box;
         var topppp = this.game.wrap_v ? 0 : grid_box[1];
         var bottom = this.game.wrap_v ? this.canvasHeight() : grid_box[3];
         var lefttt = this.game.wrap_h ? 0 : grid_box[0];
         var rightt = this.game.wrap_h ? this.canvasWidth() : grid_box[2];
         //vertical lines
         ctx.save();
         ctx.beginPath();
         for(var i=0;i<this.game.w;i++){
            var pt = view.nodeToPoint([0,i]);
            //var p = i / (this.game.w-1);
            //var x = grid_box[0] + (p * this.grid_w)
            var x = pt[0];
            this.v_lines[i] = x;
            ctx.lineWidth = 1.2;
            ctx.moveTo(x, topppp);
            ctx.lineTo(x, bottom);
         }
         // h lines
         for(var i=0;i<this.game.h;i++){
            var pt = view.nodeToPoint([i,0]);
            //var p = i / (this.game.h-1);
            //var y = grid_box[1] + (p * this.grid_h);
            var y = pt[1];
            this.h_lines[i] = y;
            ctx.lineWidth = 1.2;
            ctx.moveTo(lefttt, y);
            ctx.lineTo(rightt, y);
         }
         ctx.stroke();
         ctx.closePath();
         // star points?
         if(this.game.h == 19 && this.game.w == 19){
            var nodes = [[3,3],[15,15], [15,3], [3,15], [9,9],
               [3,9],[9,3],[9,15],[15,9]];
            var star_r = view.canvasWidth() / 180;
            $.each(nodes,function(){
               ctx.fillStyle   = '#000';
               var pt = view.nodeToPoint(this);
               ctx.beginPath();
               ctx.moveTo(pt[0]+star_r, pt[1]);
               ctx.arc(pt[0], pt[1] , star_r, 0, Math.PI*2, true); 
               ctx.closePath();
               ctx.fill();
               //ctx.fillRect(pt[0]-star_size/2, pt[1]-star_size/2, star_size,star_size);
            });
         }
         ctx.restore();
         //copy empty board to paste over removed stuff.
         this.empty_board_image_data = 
            ctx.getImageData(0, 0, ctx.canvas.width, ctx.canvas.height);
         //fctx.drawImage(this.intermediateCanvas,0,0); 
         this.redrawFinalWithOffset();
         this.activateGame();
      },


      finagleCanvas : function(cnvs){
         var view = this;
         this.setFinalCanvas (cnvs);

         var calc_canvas_dims = this.determineCanvasDims();
         this.calc_stone_size = calc_canvas_dims.stone_size;
         cnvs.width = calc_canvas_dims.w;
         cnvs.height = calc_canvas_dims.h;
         
         // this sucks. how to best determine available space?
         $('div.middoblock').width ( Math.floor(cnvs.width) );
         var margin = this.margin = this.calc_stone_size / 2;
      // TODO: kill grid_box
         var grid_box = [margin,margin,cnvs.width-margin, cnvs.height-margin];
         this.grid_box = grid_box;
         this.grid_w = grid_box[2] - grid_box[0];
         this.grid_h = grid_box[3] - grid_box[1];
         this.node_w = this.calc_stone_size; //this.grid_w / (this.game.w-1);
         this.node_h = this.calc_stone_size; //this.grid_w / (this.game.w-1);
         //this.node_h = this.grid_h / (this.game.h-1);

         var ic = $('<canvas />')[0];
         this.setIntermediateCanvas(ic);
         ic.width = cnvs.width;
         ic.height = cnvs.height;

         this.offset_x = 0;
         this.offset_y = 0;

         // mouse handler..
         $(this.getFinalCanvas()).mousedown(function(e_down){
            // left mouse button == Move!
            var down_button = e_down.which;
            if(down_button == 1){
               if(view.in_grab == true)
                  return;
               if(view.game.getAsstatus() == 'finished')
                  return;
               var point = mouseEventToRelative(e_down);
               var boardnode = view.canvasXYToNode(point[0],point[1]);
               if(!boardnode){ return;}
               if(view.game.getAsstatus() == 'active'){
                  if(view.can_move()) {
                     view.game.attemptMove(boardnode);
                  }
                  return;
               }
               if(view.game.getAsstatus() == 'scoring'){
                  //if(view.can_toggle_chain_state()) {
                     view.game.attemptTransanimate(boardnode);
                  //}
                  return;
               }
            }
            // right mouse button == drag!
            // right or middle, resp.
            if(down_button == 3 || down_button == 2){
               if(view.in_grab == true)
                  return;
               e_down.preventDefault(); //no menu.
               //if(this.wrap_v || this.wrap_h){
               view.grabx = e_down.pageX;
               view.graby = e_down.pageY;
               view.movex = e_down.pageX;
               view.movey = e_down.pageY; //?
               view.in_grab = true;
               view.in_grab_button = down_button;
               $(document).mousemove(function(e_move){
                  view.movex = e_move.pageX;
                  view.movey = e_move.pageY;
                  view.redrawFinalWithOffset();
               });
               $(document).mouseup(function(e_up){
                  if(e_up.which != down_button)
                     return;
                  view.in_grab = false;
                  $(document).unbind('mouseup');
                  $(document).unbind('mousemove');
                  var dispx = view.movex - view.grabx;
                  var dispy = view.movey - view.graby;
                  view.game.log('DRAGGED X '+dispx);
                  view.game.log('DRAGGED Y '+dispy);
                  view.graby = view.grabx = 0;
                  view.movey = view.movex = 0;
                  view.offset_x += dispx;
                  view.offset_y += dispy;
                  view.redrawFinalWithOffset();
               });
            }
         });
         $(view.getFinalCanvas()).bind('contextmenu',function(e){e.preventDefault();return false});

         // keys for scrolling.
         $(document).keydown(function(e){
            var c = String.fromCharCode(e.which);
            if(c == 'A' || c == 'H'){
               view.offset_x += +20;
            }
            else if(c == 'D' || c == 'L'){
               view.offset_x += -20;
            }
            else if(c == 'K' || c == 'W'){
               view.offset_y += +20;
            }
            else if(c == 'S' || c == 'J'){
               view.offset_y += -20;
            }
            //   relevantView.virtuallyGoToStart();
            else if (e.keyCode == 37) { //left arrow
               relevantView.virtuallyGoBackwards();
               e.stopPropagation();
            }
            else if (e.keyCode == 39) { //right arrow
               relevantView.virtuallyGoForwards();
               e.stopPropagation();
            }
            else {return}
            view.redrawFinalWithOffset();
         });

         this.game.on('new_game_event', function(){ 
            if(view.virtualMoveNum == view.game.game_events.length-1){ 
               view.virtuallyGoToEnd();
            }
         });

         this.canvasFinagled = true; //pretty darn finagled.
      }, //end finagleCanvas

      // guess board canvas dims from window dims.
      // should change upon resize. TODO: to 'view'
      determineCanvasDims : function(){
         var win_w = $(window).width();
         var win_h = $(window).height();
         var avail_w = win_w *.95 - 40;
         avail_w -= $('div.leftoblock').width();
         avail_w -= $('div.rightoblock').width();
         var avail_h = win_h - 60;
         if(avail_w < 350)
            avail_w = 350;
         if(avail_h < 350)
            avail_h = 350;
         var max_stone_size_x = avail_w / this.game.w;
         var max_stone_size_y = avail_h / this.game.h;
         var stone_size;
         if(max_stone_size_x > max_stone_size_y){
            stone_size = max_stone_size_y;
         } else {
            stone_size = max_stone_size_x;
         }
         stone_size = Math.floor(stone_size);
         var calc_canvas_w  =  Math.floor(stone_size * this.game.w);
         var calc_canvas_h =   Math.floor(stone_size * this.game.h);
         return {
            'stone_size': stone_size,
            'w': calc_canvas_w,
            'h': calc_canvas_h,
         };
      },

      draw : function(){
         if(!this.getIntermediateCanvas()){
            alert('no canvas! ' + this.canvas);
            return;
         }
         var view = this;
         var ctx = this.getIntermediateCanvas().getContext('2d');
         ctx.fillStyle = 'red';
         //var bg = $("#wood-bg")[0];
         this.image_urls = {w:"/w.png",b:"/b.png",bg:"/jigo-woodgrain.jpg"};
         //this.image_urls = {w:"/w.png",b:"/b.png",bg:"/light_coloured_wood_200142-vertical.JPG"};
         //http://www.flickr.com/photos/wwarby/6963362742/in/set-72157625097924639/
         //this.image_urls = {w:"/w.png",b:"/b.png",bg:"/birch_tex.jpg"};
         this.images = new Object();
         this.images.b = new Image();
         this.images.b.src = this.image_urls["b"];
         this.images.w = new Image();
         this.images.w.src = this.image_urls["w"];

         this.images.bg = new Image();
         this.images.bg.src = this.image_urls['bg'];
         //necessary nonsense for firefox having usable graphics??
         this.FOO_CONTAINER = $('<div class="sorta-hidden"/>')
            .append(this.images.bg)
            .append(this.images.w)
            .append(this.images.b);
         $('body').append(this.FOO_CONTAINER);

         $(this.FOO_CONTAINER).imagesLoaded( function($images,$proper,$broken){
            view.game.log( $images.length + ' images total have been loaded' );
            view.game.log( $proper.length + ' properly loaded images' );
            view.game.log( $broken.length + ' broken images' );
            var ctx = view.getIntermediateCanvas().getContext('2d');
            ctx.drawImage(view.images.bg,0,0, ctx.canvas.width * 1.1111,ctx.canvas.height * 1.1111);
            view.drawLines();
            view.acquire_extra_graphics();
         });
      },

      // constant for the same i & the same incarnation of the view... lame & ad-hoc.
      random_w_stone_img: function(i){
      //   alert(i);
         if(!this.extra_w_stones_acquired)
            return this.images.w;
         if(!this.lambdphli)
            this.lambdphli = Math.floor(Math.random()*100) + 33;
         var i = moddd(i, this.lambdphli);
         i = moddd(i,15);
         return this.extra_w_stones[i];
      },
      acquire_extra_graphics : function(){
         var view = this;
         this.extra_w_stones = [];
         this.BAR_CONTAINER = $('<div class="sorta-hidden"/>');
         for(var i=1; i<=15; i++){
            var url = '/w'+i+'.png';
            var img = new Image();
            img.src = url;
            this.extra_w_stones.push(img);
            this.BAR_CONTAINER.append(img);
         }
         $(this.BAR_CONTAINER).imagesLoaded( function($images,$proper,$broken){
            view.extra_w_stones_acquired = true;
            view.game.log($images.length +' imgs, broken: '+$broken.length);
         });
         $('body').append(this.BAR_CONTAINER);
      },

      applyBoardDelta : function(boardDelta){
         var view = this;
         this.getVirtualBoard().applyBoardDelta(boardDelta);
         if(boardDelta.add != null){
            $.each(boardDelta.add, function(color,nodes){
               $.each(nodes, function(){
                  var node = this;
                  view.dropStone(color, node);
               });
            });
         }
         if(boardDelta.remove != null){
            $.each(boardDelta.remove, function(color,nodes){
               $.each(nodes, function(){
                  var node = this;
                  view.clearNode(node);
               });
            });
         }
      },
      resetNode : function(node){
         var at_node = this.getVirtualBoard().getStoneAtNode(node);
         if(at_node){
            this.dropStone(at_node, node);
         }
         else {
            this.clearNode(node);
         }
      },
      dropStone : function(stone, node){
         if (this.shadow_node)
            this.eraseShadowStone();
         var ictx = this.intermediateCanvas.getContext('2d');
         var fctx = this.finalCanvas.getContext('2d');
         var point = this.nodeToPoint(node);
         //alert(node[0] +','+ node[1] +'||'+ point[0] +','+ point[1]);
         var stone_img = this.images[stone];
         if(stone=='w')
            stone_img = this.random_w_stone_img(node[0]*47 + node[1]*61);
         ictx.drawImage(stone_img,
               point[0] - this.node_w/2, point[1]-this.node_h/2,
               this.node_w, this.node_h);
         this.redrawNodeOnFinal(node);
      },
      redrawNodeOnFinal : function(node){
         var point = this.nodeToPoint(node);
         var fctx = this.finalCanvas.getContext('2d');
         var orig_x = point[0] - this.node_w/2;
         var orig_y = point[1] - this.node_h/2;
         var offset_x = this.game.wrap_h ? this.offset_x : 0;
         var offset_y = this.game.wrap_v ? this.offset_y : 0;

         var cwidth = this.finalCanvas.width;
         var cheight = this.finalCanvas.height;
         var new_x = moddd(orig_x + offset_x, cwidth);
         var new_y = moddd(orig_y + offset_y, cheight);
         var virtual_nodes = [
            [new_x, new_y],
            [new_x, new_y - cheight],
            [new_x - cwidth, new_y],
            [new_x - cwidth, new_y - cheight],
         ];
         for(var i=0;i<4;i++){
            fctx.drawImage(this.intermediateCanvas,
                  orig_x, orig_y,
                  this.node_w, this.node_h,
                  virtual_nodes[i][0], virtual_nodes[i][1],
                  this.node_w, this.node_h);
         }
      },
      redrawFinalWithOffset : function(){
         var fctx = this.getFinalCanvas().getContext('2d');
         var offset_x = this.offset_x;
         var offset_y = this.offset_y;
         if(this.in_grab){
            var dispx = this.movex - this.grabx;
            var dispy = this.movey - this.graby;
            offset_x += dispx;
            offset_y += dispy;
         }
         if(!this.game.wrap_v)
            offset_y = 0;
         if(!this.game.wrap_h)
            offset_x = 0;
         var cwidth = this.finalCanvas.width;
         var cheight= this.finalCanvas.height;
         var wrapping_offsets = [
            [moddd(offset_x , cwidth), moddd(offset_y , cheight)],
            [moddd(offset_x , cwidth)-cwidth, moddd(offset_y , cheight)],
            [moddd(offset_x , cwidth), moddd(offset_y , cheight)-cheight],
            [moddd(offset_x , cwidth)-cwidth, moddd(offset_y , cheight)-cheight]
         ];
         for(var i=0;i<4;i++){   
            fctx.drawImage(this.intermediateCanvas,
                  0,0,cwidth,cheight, //src
                  wrapping_offsets[i][0], wrapping_offsets[i][1], cwidth,cheight); //dest
         }
      },

      eraseLastMoveMark: function(){
         if( this.lastMoveMarkColor == null) //nothing marked.
            return;
         this.dropStone (this.lastMoveMarkColor, this.lastMoveMarkNode);
         this.redrawNodeOnFinal(this.lastMoveMarkNode);
         this.lastMoveMarkColor = null;
         this.lastMoveMarkNode = null;
      },
      markLastMove: function(){
         if(this.virtualMoveNum == 0)
            return;
         var boardDelta = this.game.game_events[this.virtualMoveNum-1].delta.board;
         if(boardDelta == null)
            return;
         if(boardDelta.add == null){
            this.game.log('FOOOOOOOOO?');
            return;
         }
         var color = Object.keys(boardDelta.add)[0]
         var node_to_mark = boardDelta.add[color][0];
         this.lastMoveMarkColor = color;
         this.lastMoveMarkNode = node_to_mark;

         var point = this.nodeToPoint(node_to_mark);
         var x = point[0];
         var y = point[1];
         var r = this.node_w * .25;
         var ctx = this.getIntermediateCanvas().getContext('2d');
         ctx.save();
         ctx.beginPath();
         ctx.lineWidth=4;
         ctx.strokeStyle= (color == 'w') ? "black" : 'white';
         ctx.moveTo(x+r, y);
         ctx.arc(x, y, r, 0, Math.PI*2, true); 
         ctx.closePath();
         ctx.stroke();
         ctx.restore();
         this.redrawNodeOnFinal(node_to_mark);
      },
      putBoxOnNode : function(node_to_mark, style){
         var point = this.nodeToPoint(node_to_mark);
         var x = point[0];
         var y = point[1];
         //x,y == center. so...
         var dims = this.node_w * .41;
         x -= dims/2;
         y -= dims/2;
         var ctx = this.getIntermediateCanvas().getContext('2d');
         ctx.beginPath();
         ctx.fillStyle = style ? style : "rgb(233,233,233)";
         ctx.rect(x,y,dims,dims);
         ctx.fill();
         this.redrawNodeOnFinal(node_to_mark);
      },
      putDotOnNode : function(node_to_mark, style){
         var ctx = this.getIntermediateCanvas().getContext('2d');
         var r = this.node_w * .14;
         var point = this.nodeToPoint(node_to_mark);
         var x = point[0];
         var y = point[1];

         ctx.fillStyle = style ? style : "rgb(233,233,233)";
         ctx.beginPath();
         ctx.moveTo(x+r, y);
         ctx.arc(x, y, r, 0, Math.PI*2, true); 
         ctx.fill();
         this.redrawNodeOnFinal(node_to_mark);
      },

      // clear shadow stone. replace with empty board section.
      eraseShadowStone : function(){
         this.clearNode(this.shadow_node);
         this.shadow_node = null;
      },
      clearNode : function(node){
         var ctx = this.getIntermediateCanvas().getContext('2d');
         var point = this.nodeToPoint(node);
         var x = point[0] - this.node_w/2;
         var y = point[1] - this.node_h/2;
         ctx.putImageData(this.empty_board_image_data, 
               0,0,x,y, this.node_w, this.node_h);
         this.redrawNodeOnFinal(node);
      },
      displayShadowStone : function(board_node){
         var ctx = this.intermediateCanvas.getContext('2d');

         var rm_old = false;
         var draw_new = false;

         if (board_node != null && this.shadow_node != null){
            if (board_node[0]!=this.shadow_node[0] || board_node[1]!=this.shadow_node[1]){
               draw_new = true;
               rm_old = true;
            }
         } else if (board_node == null && this.shadow_node != null){
            rm_old = true;
         } else if (board_node != null){
            draw_new = true;
         }
         // don't do shadow if an actual stone is there.
         var colliding_stone = this.game.getActual_board().getStoneAtNode(board_node);
         if (colliding_stone)
            draw_new = false;

         if(rm_old == true) {
            this.eraseShadowStone();
         }

         if(draw_new == true) {
            var point = this.nodeToPoint(board_node);
            ctx.globalAlpha = .5;
            ctx.drawImage(this.images[this.game.actual_turn],
               point[0] - this.node_w/2, point[1]-this.node_h/2,
               this.node_w, this.node_h);
            this.shadow_node = board_node;
            ctx.globalAlpha = 1;
            this.redrawNodeOnFinal(board_node);
         }
      },
      nodeToPoint : function(node){
         var row = node[0];
         var col = node[1];
         //var x = this.grid_box[0] + this.grid_w * col / (this.game.w-1);
         //var y = this.grid_box[1] + this.grid_h * row / (this.game.h-1);
         if(typeof (col) == 'string')
            col = node[1] = parseInt(col);
         if(typeof (row) == 'string')
            row = node[0] = parseInt(row);
         //   alert('col should be number, but is a '+ typeof(col));
         var x = this.node_w * (col + .5);
         var y = this.node_h * (row + .5);
         
         //alert(col +','+ row +'||'+ x +','+ y + '[<{}>] '+ this.node_w);
         return [x,y];
      },
      canvasXYToNode : function(x,y){
         var row = -1, col = -1;
         var reach_x = this.node_w/2;
         var reach_y = this.node_h/2;
         if(this.game.wrap_h){
            x -= this.offset_x;
            x=moddd(x,this.getFinalCanvas().width);
         }
         if(this.game.wrap_v){
            y -= this.offset_y;
            y=moddd(y,this.getFinalCanvas().height);
         }
         for (var i=0;i<this.game.w;i++){
            var node_x = this.grid_box[0] + i*this.node_w;
            if( (x > node_x-reach_x) && (x < node_x+reach_x)){
               col = i;
               break;
            }
         }
         for (var i=0;i<this.game.h;i++){
            var node_y = this.grid_box[1] + i*this.node_h;
            if( (y > node_y-reach_y) && (y < node_y+reach_y)){
               row = i;
               break;
            }
         }
         if (row == -1 || col == -1){
            return null;
         }
         return [row,col];
      },

      activateGame : function(){
         var view = this;
         $(this.getFinalCanvas()).mousemove(function(e){
            if(!view.can_move()) {return;}
            var point = mouseEventToRelative(e);
            var boardnode = view.canvasXYToNode(point[0],point[1]);
            if(!boardnode){ return;}
            view.displayShadowStone(boardnode);
         });
         this.game.openSocket();
         this.loadMoveSound();
      },

      // either show deads/territory or mark the current move...
      decorate: function(){
         if(this.game.asstatus == 'scoring' && this.viewIsCurrent()){
            if ( this.game.latestScorable != null ){
               this.game.log('decorating score; dead stones & territory...');
               this.markLastScorable();
               this.scorableMarked = 1;
            }
         }
         else {
            this.markLastMove();
            this.lastMoveMarked = 1;
         }
      },
      undecorate: function(){
         if ( this.scorableMarked ){
            this.unmarkMarkedScorable();
         }
         if ( this.lastMoveMarked ){
            this.eraseLastMoveMark();
         }
         else if (this.asstatus == 'scoring'){
         }
      },

      // Time controls
      virtuallyGoToMove : function(destMoveNum){
         var view = this;
         this.game.log ('gotomove: '+ this.virtualMoveNum + '->' + destMoveNum);
         if(destMoveNum == this.virtualMoveNum){
            return;
         }
         this.undecorate();
         if(destMoveNum > this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_apply = this.game.game_events[this.virtualMoveNum];
               var delta = event_to_apply.delta;
               if(delta.board != null)
                  this.applyBoardDelta (delta.board);
               if(delta.captures != null){
                  $.each(delta.captures, function(color,delt){
                     view.virtualCaptures[color] = delt.after;
                     //view.onCapturesChange(color, delt.after);
                     view.emit('captures_change', [color, delt.after]);
                  });
               }
               this.virtualMoveNum++;
               //this.log (this.virtualMoveNum+1);
               //this.log (this.virtualMoveNum);
            }
            //this.onVirtualMoveChange(this.virtualMoveNum);
            this.emit('virtual_move_change');
            this.decorate();
            return;
         }
         // go backwards in time
         if(destMoveNum < this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_reverse = this.game.game_events[this.virtualMoveNum-1];
               var delta = event_to_reverse.delta;
               var reversed_delta = {};
               if(delta.turn != null){
                  reversed_delta.turn = {
                     before: delta.turn.after,
                     after: delta.turn.before,
                  };
               }
               if(delta.board != null){
                  reversed_delta.board = {};
                  if(delta.board.add != null)
                     reversed_delta.board.remove = delta.board.add;
                  if(delta.board.remove != null)
                     reversed_delta.board.add= delta.board.remove;
               }
               if(delta.captures  != null){
                  $.each(delta.captures, function(color,delt){
                     view.virtualCaptures[color] = delt.before;
                     //view.onCapturesChange(color, delt.before);
                     view.emit('captures_change', [color, delt.before]);
                  });
               }

               if(reversed_delta.board != null){
                  this.applyBoardDelta (reversed_delta.board);
               }
               //this.applyCapturesDelta(reversed_delta.captures);

               this.virtualMoveNum--;
            }
            //this.onVirtualMoveChange(this.virtualMoveNum);
            this.emit('virtual_move_change');
            this.decorate();
            return;
         }
      },

      virtuallyGoToStart : function(){
         this.virtuallyGoToMove(0);
      },
      virtuallyGoToEnd: function(){
         this.virtuallyGoToMove(this.game.game_events.length);
      },
      virtuallyGoBackwards : function(){
         if(this.virtualMoveNum == 0)
            return;
         this.virtuallyGoToMove(this.virtualMoveNum-1);
      },
      virtuallyGoForwards : function(){
         if(this.viewIsCurrent())
            return;
         this.virtuallyGoToMove(this.virtualMoveNum+1);
      },
      viewIsCurrent : function(){
         if(this.virtualMoveNum == this.game.game_events.length)
            return true;
         return false;
      },
      
      loadMoveSound : function(){
         for(var i=0;i<3; i++){ //3 'channels'
            var audioElement = 
               $("<audio class='stone-sound' src='/27826__erdie__sword01.ogg' id='stone-sound-"+i+"' />");
            $('body').append(audioElement);
         }
         this.audio_play_count = 0;
      },
      playMoveSound : function(){
         var i = this.audio_play_count++;
         i=i%3; //bleh.
         var audioElement = $("audio#stone-sound-"+i);
         audioElement[0].play();
      },
      handleScorableChange : function(){
         if(this.viewIsCurrent()){
            this.game.log('CHANGING SCORABLE VIEW.');
            this.decorate();
         }
         else{
            this.game.log('CHANGING SCORABLE; UNVIEWED..');
         }
      },
      unmarkMarkedScorable : function(){
         this.game.log('marking scorable. ljasdf');
         var view = this;
         var scorable = this.markedScorable;
         if(scorable == null) {return}
         $.each(scorable.terr.w, function(){
            view.resetNode(this)});
         $.each(scorable.terr.b, function(){
            view.resetNode(this)});
         $.each(scorable.dead.w, function(){
            view.resetNode(this)});
         $.each(scorable.dead.b, function(){
            view.resetNode(this)});
         this.markedScorable = null;
      },
      markLastScorable : function(){
         this.game.log('marking scorable. ljasdf');
         var view = this;
         var scorable = this.game.latestScorable;
         if(this.markedScorable){ //something is already marked
            if(scorable == this.markedScorable) {return} //latest is already marked
            this.unmarkMarkedScorable(); // unmark.
         }
         $.each(scorable.terr.w, function(){
            view.putDotOnNode(this, 'white'); });
         $.each(scorable.terr.b, function(){
            view.putDotOnNode(this, 'black'); });
         $.each(scorable.dead.w, function(){
            view.putBoxOnNode(this, 'black'); });
         $.each(scorable.dead.b, function(){
            view.putBoxOnNode(this, 'white'); });
         this.markedScorable = scorable;
      },
   },
});



