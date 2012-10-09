'use strict';

// Goal:
// So Game has a View, game & view each have GridBoards.
// view has decoration & canvases...
// game has no reference to view... only callbacks?


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


Class( 'GridBoard', {
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
      applyDelta : function(delta){
         var board = this;
         var removes = delta.remove;
         var adds = delta.add;
         $.each(removes, function(){
            var node = this[1];
            board.clearNode(node);
         });
         $.each(adds, function(){
            var node = this[1];
            var stone = this[0];
            board.setNode(node, stone);
         });
      },
   },
});


Class('CinderblockGame', {
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
      onNewGameEvent : function(delta){},
      onTotalMovesChange : function(new_count){},
      onGameEnd : function(e){},
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
         return view;
      },

      handleMoveEvent : function(move_event){
         this.game_events.push(move_event);
         this.getActual_board().applyDelta(move_event.delta);
         this.actual_turn = move_event.turn_after;
         this.onNewGameEvent(move_event); //cb
         this.onTotalGameEventsChange (this.game_events.length);
      },
      handlePassEvent : function(pe){
         this.game_events.push(pe);
         //this.getActual_board().applyDelta(move_event.delta);
         this.actual_turn = pe.turn_after;
         this.onNewGameEvent(pe); //cb
         this.onTotalGameEventsChange (this.game_events.length);
      },
      handleResignEvent : function(re){
         this.game_events.push(re);
         //this.getActual_board().applyDelta(move_event.delta);
         this.actual_turn = re.turn_after;
         this.onNewGameEvent(re); //cb
         this.onTotalGameEventsChange (this.game_events.length);
         this.onGameEnd(re); //cb
      },
   
      // funky callback things.
      setOnGameEnd : function(cb){
         this.onGameEnd = cb;
      },
      setOnNewGameEvent : function(cb){
         this.onNewGameEvent = cb;
      },
      setOnTotalGameEventsChange : function(cb){
         this.onTotalGameEventsChange = cb;
      },


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
            if(msg.type == 'pass'){
               game.handlePassEvent(msg);
            }
            if(msg.type == 'resign'){
               game.handleResignEvent(msg);
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
               "stone": this.actual_turn,
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
      attemptToggle : function(node){
         var attempt = {
            action: 'attempt_toggle',
            resign_attempt: {
               "node" : node,
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



Class ('CinderblockView', {
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
      virtualCaptures: {is:'ro',init: {w:0,b:0}},
      canvasFinagled : {is:'rw', required:false},
      onVirtualMoveChange : function(move_num){},
      onCapturesChange : function(color, new_val){},
      state : {is : 'rw', init : 'void'},
   },
   methods: {
      canvasWidth:  function(){return this.getFinalCanvas().width},
      canvasHeight: function(){return this.getFinalCanvas().height},


      can_move : function(){
         if(PORTAL_DATA.role == 'watcher')
            return 0;
         if(this.virtualMoveNum != this.game.game_events.length)
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
            if(e_down.which == 1){
               var point = mouseEventToRelative(e_down);
               var boardnode = view.canvasXYToNode(point[0],point[1]);
               if(!boardnode){ return;}
               if(view.can_move()) {
                  view.game.attemptMove(boardnode);
                  return;
               }
               if(view.can_toggle_chain_state()) {
                  view.game.attemptToggle(boardnode);
                  return;
               }
            }
            // right mouse button == drag!
            if(e_down.which == 3){
               e_down.preventDefault(); //no menu.
               //if(this.wrap_v || this.wrap_h){
               view.grabx = e_down.pageX;
               view.graby = e_down.pageY;
               view.in_grab = true;
               $(document).mousemove(function(e_move){
                  view.movex = e_move.pageX;
                  view.movey = e_move.pageY;
                  view.redrawFinalWithOffset();
               });
               $(document).mouseup(function(e_move){
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

         this.game.setOnNewGameEvent(function(move_data){
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

      applyDeltaToCanvas : function(delta){
         var view = this;
         var removes = delta.remove;
         var adds = delta.add;
         $.each(removes, function(){
            var node = this[1];
            view.clearNode(node);
         });
         $.each(adds, function(){
            var stone = this[0];
            var node = this[1];
            view.dropStone(stone, node);
         });
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
         if( this.lastMoveMarkStone == null) //nothing marked.
            return;
         this.dropStone (this.lastMoveMarkStone, this.lastMoveMarkNode);
         this.redrawNodeOnFinal(this.lastMoveMarkNode);
         this.lastMoveMarkStone = null;
         this.lastMoveMarkNode = null;
      },
      markLastMove: function(){
         if(this.virtualMoveNum == 0)
            return;
         var delta = this.game.game_events[this.virtualMoveNum-1].delta;
         if(delta == null)
            return;
         if(delta.add.length != 1){
            this.game.log('FOOOOOOOOO?');
            return;
         }
         var stone_to_mark = delta.add[0][0];
         var node_to_mark = delta.add[0][1];
         this.lastMoveMarkStone = stone_to_mark;
         this.lastMoveMarkNode = node_to_mark;

         var point = this.nodeToPoint(node_to_mark);
         var x = point[0];
         var y = point[1];
         var r = this.node_w * .25;
         var ctx = this.getIntermediateCanvas().getContext('2d');
         ctx.save();
         ctx.beginPath();
         ctx.lineWidth=4;
         ctx.strokeStyle= (stone_to_mark == 'w') ? "black" : 'white';
         ctx.moveTo(x+r, y);
         ctx.arc(x, y, r, 0, Math.PI*2, true); 
         ctx.closePath();
         ctx.stroke();
         ctx.restore();
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
      setOnVirtualMoveChange : function(cb){
         this.onVirtualMoveChange = cb;
      },
      setOnCapturesChange: function(cb){
         this.onCapturesChange = cb;
      },

      // Time controls
      virtuallyGoToMove : function(destMoveNum){
         var view = this;
         this.game.log ('gotomove: '+ this.virtualMoveNum + '->' + destMoveNum);
         if(destMoveNum == this.virtualMoveNum){
            return;
         }
         this.eraseLastMoveMark();
         if(destMoveNum > this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_apply = this.game.game_events[this.virtualMoveNum];
               if(event_to_apply.delta != null)
                  this.applyDeltaToCanvas(event_to_apply.delta);
               if(event_to_apply.captures != null){
                  $.each(event_to_apply.captures, function(color,diff){
                     view.virtualCaptures[color] += diff;
                     view.onCapturesChange(color, view.virtualCaptures[color]);
                  });
               }
               this.virtualMoveNum++;
               //this.log (this.virtualMoveNum+1);
               //this.log (this.virtualMoveNum);
            }
            this.onVirtualMoveChange(this.virtualMoveNum);
            this.markLastMove();
            return;
         }
         // go backwards in time
         if(destMoveNum < this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_reverse = this.game.game_events[this.virtualMoveNum-1];
               var delta = event_to_reverse.delta;
               if(delta != null){
                  var removes = delta.remove;
                  var adds = delta.add;
                  var reversed_delta = {
                     'add' : removes,
                     'remove' : adds,
                  };
                  this.applyDeltaToCanvas(reversed_delta);
               }
               if(event_to_reverse.captures != null){
                  $.each(event_to_reverse.captures, function(color,diff){
                     view.virtualCaptures[color] -= diff;
                     view.onCapturesChange(color, view.virtualCaptures[color]);
                  });
               }
               this.virtualMoveNum--;
            }
            this.onVirtualMoveChange(this.virtualMoveNum);
            this.markLastMove();
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
         if(this.virtualMoveNum == this.game.game_events.length)
            return;
         this.virtuallyGoToMove(this.virtualMoveNum+1);
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
   },
});



