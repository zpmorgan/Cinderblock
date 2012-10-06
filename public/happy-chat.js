Class('HappyChat', {
   has: {
      elem: {is:'ro', required:true},
      messages_elem: {is:'ro', required: true},
      txtfield_elem: {is:'ro', required: true},
      onMsgTyped: {is:'rw',init:function(){}},
   },
   methods:{
      displayMessage: function(happy_msg_event){
         //_messages_elem.append(msg.text);
         var happy_raw_text = happy_msg_event.text;
         var happy_epoch_ms = happy_msg_event.time;
         var happy_speaker = happy_msg_event.speaker;
         // event: {text, speaker, time_ms};
         // var msgbox = this.messages_elem;
         var msgdiv = $('<div class="happy-message" />');

         var msg_text_div = $('<div class="happy-submessage floatleft" />');
         msg_text_div.css('width', "60%");
         var msg_time_div = $('<div class="happy-submessage floatright" />');
         msg_time_div.css('width', "30%");

         var msg_body = $('<p />');
         if(happy_speaker){
            msg_body.append($( '<span style="font-weight:bold;" />').text(happy_speaker))
         } else {
            msg_body.append($( '<span style="font-style:italic;" />').text('anon'))
         }
         msg_body.append(': ');
         msg_body.append($( '<span />').text(happy_raw_text));
         msg_text_div.append(msg_body);

         if (!happy_epoch_ms)
            happy_epoch_ms = 45;
         if (typeof(happy_epoch_ms) == 'string')
            happy_epoch_ms = parseInt(happy_epoch_ms);
         var moment_said = moment(happy_epoch_ms);
         //console.log(epochms);
         //console.log(sad_event);
         msg_time_div.append($('<p />').append(moment_said.format('LT')));

         msgdiv.append(msg_text_div);
         msgdiv.append(msg_time_div);
         this.messages_elem.prepend(msgdiv);
      },
   },
});


(function( $ ) {
   $.fn.happyChat = function(args) {
      var msgs = $('<div class="happy-chat-messages" />');
      var input = $('<input type="textfield" />');
      this.append(input);
      this.append(msgs);
      console.log(msgs);
      console.log(input);
      var h = new HappyChat({
         "elem": this,
         messages_elem: msgs,
         txtfield_elem: input,
      });
      return h;
      // Do your awesome plugin stuff here
   };
})( jQuery );

