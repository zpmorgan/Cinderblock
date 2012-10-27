Class('HappyChat', {
   has: {
      ws_url_base: {is:'ro', required:true},
      channel: {is:'ro', required:true},
      elem: {is:'ro', required:true},
      messages_elem: {is:'ro', required: true},
      txtfield_elem: {is:'ro', lazy: false, init: _build_input_field},
   },
   methods:{
      displayMessage: function(happy_msg_event){
         var happy_raw_text = happy_msg_event.text;
         var happy_epoch_ms = happy_msg_event.time_ms;
         var happy_speaker = happy_msg_event.speaker;
         var msgdiv = $('<div class="happy-message" />');

         var msg_text_div = $('<div class="happy-submessage-body" />');
         var msg_time_div = $('<div class="happy-submessage-time" />');

         var msg_body = $('<p />');
         if(happy_speaker){
            msg_body.append($( '<span style="font-weight:bold;" />').text(happy_speaker))
         } else {
            msg_body.append($( '<span style="font-style:italic;" />').text('anon'))
         }
         msg_body.append(': ');
         msg_body.append($( '<span />').text(happy_raw_text));
         msg_text_div.append(msg_body);

         var time_string = '';

         if (!happy_epoch_ms){
            time_string = '??:??';
         }
         else{
            if (typeof(happy_epoch_ms) == 'string')
               happy_epoch_ms = parseInt(happy_epoch_ms);
            var moment_said = moment(happy_epoch_ms);
            time_string = moment_said.format('LT');
         }
         //console.log(epochms);
         //console.log(sad_event);
         msg_time_div.append($('<p />').text(time_string));

         msgdiv.append(msg_text_div);
         msgdiv.append(msg_time_div);
         this.messages_elem.prepend(msgdiv);

         this._msg_audio.play();
      },
      openSocket: function(){
         var hc = this;
         this.sock_url = this.ws_url_base +'/'+ this.channel;
         this.chat_sock = new WebSocket(this.sock_url);
         this.chat_sock.onmessage = function  (event) {
            var msg = $.parseJSON(event.data);
            if(msg.type == 'ping'){
               hc.chat_sock.send('{"type": "pong"}');
               return;
            }
            if(msg.type == 'pong')
               return;
            hc.displayMessage (msg);
         };
         this.chat_sock.onclose= function () {
            hc.displayMessage ({
               speaker: 'Cinderblock',
               text: 'chat socket closed.',
               time_ms: Date.now(),
            });
         };
         this.chat_sock.onopen = function () {
            hc.displayMessage ({
               speaker: 'Cinderblock',
               text: 'chat socket connected.',
               time_ms: Date.now(),
            });
            var PINGS = setInterval(function(){
               hc.chat_sock.send('{"type": "ping"}');
            }, 10000);
         };
      },
   },
   after: {
      initialize: function(){
         this.openSocket();
         var audio = $("<audio src='/43683__stijn__click6b.ogg' id='move-sound' />");
         $('body').append(audio);
         this._msg_audio = audio[0];
      },
   },
});

function _build_input_field(){
   var chat = this;
   var input_field = $('<input type="textfield" maxlength="360" class="happy-input-field" />');
   this.elem.prepend(input_field);
   input_field.keydown(function(e){
      if (e.which == 13){ // 'enter'
         if ($(this).val() == '') {
            return; }
         var happy_text = $(this).val();
         $(this).val('');
         var happy_msg_req = {
            type : 'happy_msg_req',
            text : happy_text,
            time_ms : Date.now(),
         };
         //alert(happy_text);
         chat.onMsgRequest(happy_msg_req);
         chat.chat_sock.send(JSON.stringify(happy_msg_req));
      }
      e.stopPropagation();
   });
   return input_field;
}

(function( $ ) {
   $.fn.happyChat = function(args) {
      var msgs = $('<div class="happy-chat-messages" />');
      this.append(msgs);
      console.log(msgs);
      var h = new HappyChat({
         "elem": this,
         messages_elem: msgs,
         ws_url_base: args.ws_url_base,
         channel: args.channel,
      //   txtfield_elem: input,
      });
      return h;
      // Do your awesome plugin stuff here
   };
})( jQuery );

