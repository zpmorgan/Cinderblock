

function Game(){
   this.canvas = null;
   this.w = 19;
   this.h = 19;
   this.h_lines = [];
   this.v_lines = [];

   this.move_events = [];

   this.actual_board = [];
   for(i=0;i<this.w;i++)
      this.actual_board.push([]);
}
Game.prototype.setCanvas = function(cnvs){
   this.canvas = cnvs;
   var margin = this.margin = 24;
   var grid_box = [margin,margin,cnvs.width-margin, cnvs.height-margin];
   this.grid_box = grid_box;
   this.grid_w = grid_box[2] - grid_box[0];
   this.grid_h = grid_box[3] - grid_box[1];
   this.node_w = this.grid_w / (this.w-1);
   this.node_h = this.grid_h / (this.h-1);
}

Game.prototype.draw = function(){
   if(!this.canvas){
      alert('no canvas! ' + this.canvas);
      return;
   }
   var game = this;
   var ctx = game.canvas.getContext('2d');
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
   var ctx = game.canvas.getContext('2d');
   var margin = this.margin = 24;
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
   this.activate();
}

Game.prototype.handleMoveEvent = function(move_data){
   this.move_events.push(move_data);
   var move_node = move_data.node;
   this.dropStone(move_data.stone, move_node);
   this.setActualBoardNode(move_node, move_data.stone);
}
Game.prototype.dropStone = function(stone, node){
   if (this.shadow_node)
      this.eraseShadowStone();
   var ctx = this.canvas.getContext('2d');
   var point = this.nodeToPoint(node);
   var stone_img = this.images[stone];
   ctx.drawImage(stone_img,
         point[0] - this.node_w/2, point[1]-this.node_h/2,
         this.node_w, this.node_h);
}

// clear shadow stone. replace with empty board section.
Game.prototype.eraseShadowStone = function(){
   var ctx = this.canvas.getContext('2d');
   var point = this.nodeToPoint(this.shadow_node);
   var x = point[0] - this.node_w/2;
   var y = point[1] - this.node_h/2;
   ctx.putImageData(this.empty_board_image_data, 
         0,0,x,y, this.node_w, this.node_h);
   this.shadow_node = null;
}
Game.prototype.displayShadowStone = function(board_node){
   var ctx = this.canvas.getContext('2d');

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
   }
}

Game.prototype.mouseEventToRelCoords = function(e, canvas_selector){
   var x = e.pageX - canvas_selector.offsetLeft;
   var y = e.pageY - canvas_selector.offsetTop;
   return [x,y];
}

Game.prototype.activate = function(){
   var game = this;
   $(game.canvas).mousemove(function(e){
      if(!game.can_move()) {return;}
      var point = game.mouseEventToRelCoords(e,this);
      var boardnode = game.canvasXYToNode(point[0],point[1]);
      if(!boardnode){ return;}
      game.displayShadowStone(boardnode);
   });
   $(game.canvas).mousedown(function(e){
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
   
   conn = new WebSocket('ws://127.0.0.1:3000/game/'+  PORTAL_DATA.game_id  +'/sock');
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

Game.prototype.setActualBoardNode = function(node, stone){
   if(this.actual_board[node[0]] == null)
      this.actual_board[node[0]] = [];

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
   return 1;
}

