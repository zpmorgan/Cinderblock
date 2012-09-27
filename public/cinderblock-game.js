
function GridBoard(w,h){
   this.w = w;
   this.h = h;
   this.data = [];
   for(i=0;i<this.h;i++){
      this.data.push([]);
   }
   this.shadow_decor = null;
   this.lastmove_decor = null;
}

GridBoard.prototype.getStoneAtNode = function(node){
   return this.data[node[0]][node[1]];
}
GridBoard.prototype.setNode= function(node,stone){
   this.data[node[0]][node[1]] = stone;
}
GridBoard.prototype.clearNode= function(node){
   this.data[node[0]][node[1]] = '';
}
GridBoard.prototype.applyDelta = function(delta){
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
}



function Game(opts){

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
   this.actual_board = new GridBoard(this.w, this.h);
   this.actual_turn = 'b';

   this.virtual_board = new GridBoard(this.w, this.h);
   this.virtualMoveNum = 0;
   this.onVirtualMoveChange = function(arg){};
   this.onTotalMovesChange = function(arg){};
}

Game.prototype.log = function(m){
   $('.sock-event-box').prepend(m + '<br />');
}

Game.prototype.setCanvas = function(cnvs){
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
         var point = game.mouseEventToRelCoords(e_down,this);
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
}

// guess board canvas dims from window dims.
// should change upon resize.
Game.prototype.determineCanvasDims = function(){
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
}

Game.prototype.draw = function(){
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
   this.images.bg.onload = function(){
      ctx.drawImage(game.images.bg,0,0, ctx.canvas.width * 1.1111,ctx.canvas.height * 1.1111);
      game.drawLines();
   };
   this.images.bg.src = this.image_urls['bg'];
}

Game.prototype.drawLines = function(){
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
}

Game.prototype.applyDeltaToCanvas= function(delta){
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
}
Game.prototype.FOOapplyDeltaToBoard= function(delta, board){
   var game = this;
   var removes = delta.remove;
   var adds = delta.add;
   $.each(removes, function(){
      var node = this[1];
      game.clearNodeOnBoard(node, board);
   });
   $.each(adds, function(){
      var node = this[1];
      var stone = this[0];
      game.setNodeOnBoard(node, stone, board);
   });
}
Game.prototype.handleMoveEvent = function(move_data){
   this.move_events.push(move_data);
   this.actual_board.applyDelta(move_data.delta);
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
}

Game.prototype.dropStone = function(stone, node){
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
}
Game.prototype.redrawNodeOnFinal = function(node){
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

}
Game.prototype.redrawFinalWithOffset = function(){
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

}

function moddd(i, i_max) {
      return ((i % i_max) + i_max) % i_max;
}

// clear shadow stone. replace with empty board section.
Game.prototype.eraseShadowStone = function(){
   this.clearNode(this.shadow_node);
   this.shadow_node = null;
}
Game.prototype.clearNode = function(node){
   var ctx = this.intermediateCanvas.getContext('2d');
   var point = this.nodeToPoint(node);
   var x = point[0] - this.node_w/2;
   var y = point[1] - this.node_h/2;
   ctx.putImageData(this.empty_board_image_data, 
         0,0,x,y, this.node_w, this.node_h);
   this.redrawNodeOnFinal(node);
}
Game.prototype.displayShadowStone = function(board_node){
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
   var colliding_stone = this.actual_board.getStoneAtNode(board_node);
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
}

Game.prototype.mouseEventToRelCoords = function(e, canvas_selector){
   var x = e.pageX - canvas_selector.offsetLeft;
   var y = e.pageY - canvas_selector.offsetTop;
   return [x,y];
}

Game.prototype.activate = function(){
   var game = this;
   $(game.finalCanvas).mousemove(function(e){
      if(!game.can_move()) {return;}
      var point = game.mouseEventToRelCoords(e,this);
      var boardnode = game.canvasXYToNode(point[0],point[1]);
      if(!boardnode){ return;}
      game.displayShadowStone(boardnode);
   });
   this.openSocket();
}

Game.prototype.nodeToPoint = function(node){
   var row = node[0];
   var col = node[1];
   var x = this.grid_box[0] + this.grid_w * col / (this.w-1);
   var y = this.grid_box[1] + this.grid_h * row / (this.h-1);
   return [x,y];
}

Game.prototype.canvasXYToNode = function(x,y){
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
}


Game.prototype.openSocket = function(){
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
}

// return 0 on fail, 1 on maybe?
Game.prototype.attemptMove = function(node){
   var stone_collision = this.actual_board.getStoneAtNode(node);
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
}

Game.prototype.can_move = function(){
   if(PORTAL_DATA.role == 'watcher')
      return 0;
   if (this.actual_turn != PORTAL_DATA.color)
      return 0;
   return 1;
}



Game.prototype.virtuallyGoToMove = function(destMoveNum){
         this.log (this.virtualMoveNum + '->' + destMoveNum);
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
}
Game.prototype.virtuallyGoToStart = function(){
   this.virtuallyGoToMove(0);
};
Game.prototype.virtuallyGoToEnd= function(){
   this.virtuallyGoToMove(this.move_events.length);
};
Game.prototype.virtuallyGoBackwards = function(){
   if(this.virtualMoveNum == 0)
      return;
   this.virtuallyGoToMove(this.virtualMoveNum-1);
};
Game.prototype.virtuallyGoForwards = function(){
   if(this.virtualMoveNum == this.move_events.length)
      return;
   this.virtuallyGoToMove(this.virtualMoveNum+1);
};
Game.prototype.setOnVirtualMoveChange = function(cb){
   this.onVirtualMoveChange = cb;
};
Game.prototype.setOnTotalMovesChange = function(cb){
   this.onTotalMovesChange = cb;
}


