

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
   // cached offsets for drawing:
   this.h_lines = [];
   this.v_lines = [];

   // game data:
   this.move_events = [];
   this.actual_board = [];
   this.actual_turn = 'b';
   for(i=0;i<this.h;i++)
      this.actual_board.push([]);
}
Game.prototype.setCanvas = function(cnvs){
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
}

// guess board canvas dims from window dims.
// should change upon resize.
Game.prototype.determineCanvasDims = function(){
   var win_w = $(window).width();
   var win_h = $(window).height();
   var avail_w = win_w *.95 - 40;
   avail_w -= $('div.leftoblock').width();
   avail_w -= $('div.rightoblock').width();
   var avail_h = win_h - 20;
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
   //vertical lines
   for(i=0;i<this.w;i++){
      var p = i / (this.w-1);
      var x = grid_box[0] + (p * this.grid_w)
      this.v_lines[i] = x;
      ctx.lineWidth = 1.2;
      ctx.moveTo(x, grid_box[1]);
      ctx.lineTo(x, grid_box[3]);
      ctx.stroke();
   }
   // h lines
   for(i=0;i<this.h;i++){
      var p = i / (this.h-1);
      var y = grid_box[1] + (p * this.grid_h);
      this.v_lines[i] = y;
      ctx.lineWidth = 1.2;
      ctx.moveTo(grid_box[0], y);
      ctx.lineTo(grid_box[2], y);
      ctx.stroke();
   }
   //copy empty board to paste over removed stuff.
   this.empty_board_image_data = 
      ctx.getImageData(0, 0, ctx.canvas.width, ctx.canvas.height);
   fctx.drawImage(this.intermediateCanvas,0,0); 
   this.activate();
}

Game.prototype.handleMoveEvent = function(move_data){
   var game = this;
   this.move_events.push(move_data);
   var move_node = move_data.node;
   var removes = move_data.delta.remove;
   var adds = move_data.delta.add;
   $.each(removes, function(){
      var node = this[1];
      game.clearNode(node);
      game.clearActualBoardNode(node);
   });
   $.each(adds, function(){
      var node = this[1];
      var stone = this[0];
      game.dropStone(stone, node);
      game.setActualBoardNode(node, stone);
   });
   game.actual_turn = move_data.turn_after;
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
   fctx.drawImage(this.intermediateCanvas,
         point[0] - this.node_w/2, point[1]-this.node_h/2,
         this.node_w, this.node_h,
         point[0] - this.node_w/2, point[1]-this.node_h/2,
         this.node_w, this.node_h);

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
   var colliding_stone = this.getStoneAtActualNode(board_node);
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
   $(game.finalCanvas).mousedown(function(e){
      if(!game.can_move()) {return;}
      var point = game.mouseEventToRelCoords(e,this);
      var boardnode = game.canvasXYToNode(point[0],point[1]);
      if(!boardnode){ return;}
      game.attemptMove(boardnode);
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

Game.prototype.log = function(m){
   $('.sock-event-box').prepend(m + '<br />');
}

Game.prototype.clearActualBoardNode = function(node){
   this.actual_board[node[0]][node[1]] = '';
}
Game.prototype.setActualBoardNode = function(node, stone){
   //if(this.actual_board[node[0]] == null)
     // this.actual_board[node[0]] = [];
   this.actual_board[node[0]][node[1]] = stone;
}
Game.prototype.getStoneAtActualNode = function(node){
   return this.actual_board[node[0]][node[1]];
}

// return 0 on fail, 1 on maybe?
Game.prototype.attemptMove = function(node){
   var stone_collision = this.getStoneAtActualNode(node);
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

