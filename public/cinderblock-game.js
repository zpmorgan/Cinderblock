
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

//   this.shadow_decor = null;
  // this.lastmove_decor = null;



Class('CinderblockGame', {
   has: {
     // empty_board_image_data: {is: 'rw'},
      // only stones: 
      intermediateCanvas : {is:rw},
      // marked & scrolled.
      finalCanvas : {is: rw},
      // rules:
      w : {is:'rw',init:19},
      h : {is:'rw',init:19},
      wrap_v : {is:'rw',init:false},
      wrap_h : {is:'rw',init:false},
      // cached offsets for drawing: TODO:to 'view'
      h_lines : {is:'ro',init:function(){return []}},
      v_lines : {is:'ro',init:function(){return []}},
      // game data:
      move_events :{is:'ro',init:function(){return []}},
      actual_board : {
         is: 'ro',  lazy:true, 
         isa: function () { return m.GridBoard },
         init:function () { return new GridBoard({w: this.w, h: this.h}) },
      },
      actual_turn : {is:'rw',init:'b'},
      // TODO:to 'view'
      //this.virtual_board = new GridBoard({w: this.w, h: this.h});
      actual_turn : {is:'rw',init:0},
      virtualMoveNum: {is:'rw',init:0},
      //this.onVirtualMoveChange = function(arg){};
      //this.onTotalMovesChange = function(arg){};
   },
   methods: {

      log : function(m){
         $('.sock-event-box').prepend(m + '<br />');
      },
      setCanvas : function(cnvs){
         var game = this;
         this.finalCanvas = cnvs;
         this.determineCanvasDims();
         cnvs.width = this.calc_canvas_w;
         cnvs.height = this.calc_canvas_h;
         $('div.middoblock').width ( Math.floor(this.calc_canvas_w) );
         var margin = this.margin = this.calc_stone_size / 2;
      // TODO: kill grid_box
         var grid_box = [margin,margin,cnvs.width-margin, cnvs.height-margin];
         this.grid_box = grid_box;
         this.grid_w = grid_box[2] - grid_box[0];
         this.grid_h = grid_box[3] - grid_box[1];
         this.node_w = this.grid_w / (this.w-1);
         this.node_h = this.grid_h / (this.h-1);
         this.intermediateCanvas = $('<canvas />')[0];
         this.intermediateCanvas.width = cnvs.width;
         this.intermediateCanvas.height = cnvs.height;
         this.offset_x = 0;
         this.offset_y = 0;

         // mouse handler..
         $(game.finalCanvas).mousedown(function(e_down){
            // left mouse button == Move!
            if(e_down.which == 1){
               if(!game.can_move()) {return;}
               var point = mouseEventToRelative(e_down);
               var boardnode = game.canvasXYToNode(point[0],point[1]);
               if(!boardnode){ return;}
               game.attemptMove(boardnode);
            }
            // right mouse button == drag!
            if(e_down.which == 3){
               e_down.preventDefault(); //no menu.
               //if(this.wrap_v || this.wrap_h){
               game.grabx = e_down.pageX;
               game.graby = e_down.pageY;
               game.in_grab = true;
               $(document).mousemove(function(e_move){
                  game.movex = e_move.pageX;
                  game.movey = e_move.pageY;
                  game.redrawFinalWithOffset();
               });
               $(document).mouseup(function(e_move){
                  game.in_grab = false;
                  $(document).unbind('mouseup');
                  $(document).unbind('mousemove');
                  var dispx = game.movex - game.grabx;
                  var dispy = game.movey - game.graby;
                  game.log('DRAGGED X '+dispx);
                  game.log('DRAGGED Y '+dispy);
                  game.graby = game.grabx = 0;
                  game.movey = game.movex = 0;
                  game.offset_x += dispx;
                  game.offset_y += dispy;
                  game.redrawFinalWithOffset();
               });
            }
         });
         $(game.finalCanvas).bind('contextmenu',function(e){e.preventDefault();return false});

         // keys for scrolling.
         $(document).keydown(function(e){
            var c = String.fromCharCode(e.which);
            if(c == 'A' || c == 'H'){
               game.offset_x += +20;
            }
            else if(c == 'D' || c == 'L'){
               game.offset_x += -20;
            }
            else if(c == 'K' || c == 'W'){
               game.offset_y += +20;
            }
            else if(c == 'S' || c == 'J'){
               game.offset_y += -20;
            }
            else {return}
            game.redrawFinalWithOffset();
         });
      }, //end setCanvas

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
         var max_stone_size_x = avail_w / this.w;
         var max_stone_size_y = avail_h / this.h;
         var stone_size;
         if(max_stone_size_x > max_stone_size_y){
            this.calc_stone_size = max_stone_size_y;
         } else {
            this.calc_stone_size = max_stone_size_x;
         }
         this.calc_stone_size = Math.floor(this.calc_stone_size);
         this.calc_canvas_w  =  Math.floor(this.calc_stone_size * this.w);
         this.calc_canvas_h =   Math.floor(this.calc_stone_size * this.h);
      },

      draw : function(){
         if(!this.intermediateCanvas){
            alert('no canvas! ' + this.canvas);
            return;
         }
         var game = this;
         var ctx = game.intermediateCanvas.getContext('2d');
         ctx.fillStyle = 'red';
         //var bg = $("#wood-bg")[0];
         this.image_urls = {w:"/w.png",b:"/b.png",bg:"/light_coloured_wood_200142.JPG"};
         this.images = new Object();
         this.images.b = new Image();
         this.images.b.src = this.image_urls["b"];
         this.images.w = new Image();
         this.images.w.src = this.image_urls["w"];

         this.images.bg = new Image();
         this.images.bg.src = this.image_urls['bg'];
         //this.images.bg.onload = function(){
           // ctx.drawImage(game.images.bg,0,0, ctx.canvas.width * 1.1111,ctx.canvas.height * 1.1111);
           // game.drawLines();
         //};
         this.FOO_CONTAINER = $('<div class="sorta-hidden"/>').append(this.images.bg).append(this.images.b);
         $('body').append(this.FOO_CONTAINER);
         $(this.FOO_CONTAINER).imagesLoaded( function($images,$proper,$broken){
            game.log( $images.length + ' images total have been loaded' );
            game.log( $proper.length + ' properly loaded images' );
            game.log( $broken.length + ' broken images' );
            var ctx = game.intermediateCanvas.getContext('2d');
            ctx.drawImage(game.images.bg,0,0, ctx.canvas.width * 1.1111,ctx.canvas.height * 1.1111);
            game.drawLines();
         });
      },

      drawLines : function(){
         var game = this;
         var ctx = game.intermediateCanvas.getContext('2d');
         var fctx = game.finalCanvas.getContext('2d');
         var margin = this.margin;
         var grid_box = this.grid_box;
         var topppp = this.wrap_v ? 0 : grid_box[1];
         var bottom = this.wrap_v ? this.finalCanvas.height : grid_box[3];
         var lefttt = this.wrap_h ? 0 : grid_box[0];
         var rightt = this.wrap_h ? this.finalCanvas.width : grid_box[2];
         //vertical lines
         for(i=0;i<this.w;i++){
            var p = i / (this.w-1);
            var x = grid_box[0] + (p * this.grid_w)
            this.v_lines[i] = x;
            ctx.lineWidth = 1.2;
            ctx.moveTo(x, topppp);
            ctx.lineTo(x, bottom);
            ctx.stroke();
         }
         // h lines
         for(i=0;i<this.h;i++){
            var p = i / (this.h-1);
            var y = grid_box[1] + (p * this.grid_h);
            this.v_lines[i] = y;
            ctx.lineWidth = 1.2;
            ctx.moveTo(lefttt, y);
            ctx.lineTo(rightt, y);
            ctx.stroke();
         }
         //copy empty board to paste over removed stuff.
         this.empty_board_image_data = 
            ctx.getImageData(0, 0, ctx.canvas.width, ctx.canvas.height);
         //fctx.drawImage(this.intermediateCanvas,0,0); 
         game.redrawFinalWithOffset();
         this.activate();
      },

      applyDeltaToCanvas : function(delta){
         var game = this;
         var removes = delta.remove;
         var adds = delta.add;
         $.each(removes, function(){
            var node = this[1];
            game.clearNode(node);
         });
         $.each(adds, function(){
            var stone = this[0];
            var node = this[1];
            game.dropStone(stone, node);
         });
      },

      handleMoveEvent : function(move_data){
         this.move_events.push(move_data);
         this.getActual_board().applyDelta(move_data.delta);
         this.actual_turn = move_data.turn_after;
         //this.virtualMoveNum++;
         $('#time-slider').slider("option", "max", this.move_events.length);
         var virtual_move_num = $('#time-slider').slider('value');
         if(virtual_move_num == this.move_events.length-1){ 
            // we're monitoring current state.
            // so change canvas view automatically
            $( "#time-slider" ).slider( "option", "value", this.move_events.length );
            this.applyDeltaToCanvas(move_data.delta);
            this.virtualMoveNum ++;
            this.onVirtualMoveChange(this.virtualMoveNum);
         }
         this.onTotalMovesChange (this.move_events.length);
      },

      dropStone : function(stone, node){
         if (this.shadow_node)
            this.eraseShadowStone();
         var ictx = this.intermediateCanvas.getContext('2d');
         var fctx = this.finalCanvas.getContext('2d');
         var point = this.nodeToPoint(node);
         var stone_img = this.images[stone];
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
         var offset_x = this.wrap_h ? this.offset_x : 0;
         var offset_y = this.wrap_v ? this.offset_y : 0;

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
         var fctx = this.finalCanvas.getContext('2d');
         var offset_x = this.offset_x;
         var offset_y = this.offset_y;
         if(this.in_grab){
            var dispx = this.movex - this.grabx;
            var dispy = this.movey - this.graby;
            offset_x += dispx;
            offset_y += dispy;
         }
         if(!this.wrap_v)
            offset_y = 0;
         if(!this.wrap_h)
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


      // clear shadow stone. replace with empty board section.
      eraseShadowStone : function(){
         this.clearNode(this.shadow_node);
         this.shadow_node = null;
      },
      clearNode : function(node){
         var ctx = this.intermediateCanvas.getContext('2d');
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
         var colliding_stone = this.getActual_board().getStoneAtNode(board_node);
         if (colliding_stone)
            draw_new = false;

         if(rm_old == true) {
            this.eraseShadowStone();
         }

         if(draw_new == true) {
            var point = this.nodeToPoint(board_node);
            ctx.globalAlpha = .5;
            ctx.drawImage(this.images[PORTAL_DATA.color],
               point[0] - this.node_w/2, point[1]-this.node_h/2,
               this.node_w, this.node_h);
            this.shadow_node = board_node;
            ctx.globalAlpha = 1;
            this.redrawNodeOnFinal(board_node);
         }
      },

      activate : function(){
         var game = this;
         $(game.finalCanvas).mousemove(function(e){
            if(!game.can_move()) {return;}
            var point = mouseEventToRelative(e);
            var boardnode = game.canvasXYToNode(point[0],point[1]);
            if(!boardnode){ return;}
            game.displayShadowStone(boardnode);
         });
         this.openSocket();
      },

      nodeToPoint : function(node){
         var row = node[0];
         var col = node[1];
         var x = this.grid_box[0] + this.grid_w * col / (this.w-1);
         var y = this.grid_box[1] + this.grid_h * row / (this.h-1);
         return [x,y];
      },

      canvasXYToNode : function(x,y){
         var row = -1, col = -1;
         var reach_x = this.node_w/2;
         var reach_y = this.node_h/2;
         if(this.wrap_h){
            x -= this.offset_x;
            x=moddd(x,this.finalCanvas.width);
         }
         if(this.wrap_v){
            y -= this.offset_y;
            y=moddd(y,this.finalCanvas.height);
         }
         for (i=0;i<this.w;i++){
            var node_x = this.grid_box[0] + i*this.node_w;
            if( (x > node_x-reach_x) && (x < node_x+reach_x)){
               col = i;
               break;
            }
         }
         for (i=0;i<this.h;i++){
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

      openSocket : function(){
         var game = this;
      //   ws://127.0.0.1:3000/game/
         conn = new WebSocket(PORTAL_DATA.ws_url);
         this.sock = conn;

         conn.onmessage = function  (event) {
            game.log('msg: '+event.data);
            var data = $.parseJSON(event.data);
            //game.log(data.event_type);
            if(data.event_type == 'move'){
               game.handleMoveEvent(data.move);
            }
         };
         conn.onopen = function () {
            game.log('Socket open');
         };
         conn.onclose = function () {
            game.log('Socket close');
         };
      },

      // return 0 on fail, 1 on maybe?
      attemptMove : function(node){
         var stone_collision = this.getActual_board().getStoneAtNode(node);
         if(stone_collision)
            return 0;
         var attempt = {
            action: 'attempt_move',
            move_attempt: {
               "node" : node,
               "stone": PORTAL_DATA.color,
            }
         };
         this.sock.send(JSON.stringify(attempt));
      },

      can_move : function(){
         if(PORTAL_DATA.role == 'watcher')
            return 0;
         if (this.actual_turn != PORTAL_DATA.color)
            return 0;
         return 1;
      },



      virtuallyGoToMove : function(destMoveNum){
         this.log ('gotomove: '+ this.virtualMoveNum + '->' + destMoveNum);
         if(destMoveNum == this.virtualMoveNum){
            return;
         }
         if(destMoveNum > this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_apply = this.move_events[this.virtualMoveNum];
               this.applyDeltaToCanvas(event_to_apply.delta);
               this.virtualMoveNum++;
               //this.log (this.virtualMoveNum+1);
               //this.log (this.virtualMoveNum);
            }
            this.onVirtualMoveChange(this.virtualMoveNum);
            return;
         }
         // go backwards in time
         if(destMoveNum < this.virtualMoveNum){
            // go forwards in time
            while (destMoveNum != this.virtualMoveNum){
               var event_to_reverse = this.move_events[this.virtualMoveNum-1];
               var delta = event_to_reverse.delta;
               var removes = delta.remove;
               var adds = delta.add;
               var reversed_delta = {
                  'add' : removes,
                  'remove' : adds,
               };
               this.applyDeltaToCanvas(reversed_delta);
               this.virtualMoveNum--;
            }
            this.onVirtualMoveChange(this.virtualMoveNum);
            return;
         }
      },
      virtuallyGoToStart : function(){
         this.virtuallyGoToMove(0);
      },
      virtuallyGoToEnd: function(){
         this.virtuallyGoToMove(this.move_events.length);
      },
      virtuallyGoBackwards : function(){
         if(this.virtualMoveNum == 0)
            return;
         this.virtuallyGoToMove(this.virtualMoveNum-1);
      },
      virtuallyGoForwards : function(){
         if(this.virtualMoveNum == this.move_events.length)
            return;
         this.virtuallyGoToMove(this.virtualMoveNum+1);
      },
      // funky callbacks
      setOnVirtualMoveChange : function(cb){
         this.onVirtualMoveChange = cb;
      },
      setOnTotalMovesChange : function(cb){
         this.onTotalMovesChange = cb;
      },
   },
});

function GameZZZ(opts){

   // only board, no stones, imagedata is not a canvas
   this.empty_board_image_data = null;
   // only stones: 
   this.intermediateCanvas = null;
   // marked & scrolled.
   this.finalCanvas = null;
   // rules:
   this.w = opts.w;
   this.h = opts.h;
   this.wrap_v = opts.wrap_v;
   this.wrap_h = opts.wrap_h;

   // cached offsets for drawing:
   this.h_lines = [];
   this.v_lines = [];

   // game data:
   this.move_events = [];
   this.actual_board = new GridBoard({w: this.w, h: this.h});
   this.actual_turn = 'b';

   this.virtual_board = new GridBoard({w: this.w, h: this.h});
   this.virtualMoveNum = 0;
   this.onVirtualMoveChange = function(arg){};
   this.onTotalMovesChange = function(arg){};
}

