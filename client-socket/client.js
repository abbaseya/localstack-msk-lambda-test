const socket = new WebSocket("wss://localhost.localstack.cloud:4510");
const chunk1 = document.querySelector('textarea[name="chunk1"]');
const chunk2 = document.querySelector('textarea[name="chunk2"]');
const chunkSize = 32;
var frames = [];
var sentIdx = 0;
function send() {
  if (socket.readyState !== WebSocket.OPEN) {
    console.log("The connection was not established and the message could not be sent");
    return;
  }
  var message;
  if (chunk2.value) {
    message = JSON.stringify({
      action: '#default',
      i: 0,
      data: JSON.stringify({
        chunk: chunk2.value,
        done: true,
      }),
    });
  } else {
    message = JSON.stringify({
      action: '#default',
      i: 0,
      data: JSON.stringify({
        chunk: chunk1.value,
      }),
    });
  }
  const blob = new Blob([message], { type: 'application/octet-stream' });
  // if (message) socket.send(message);
  if (message) socket.send(blob);

  // TODO: Attemping to send fragmented frames
  // var reader = new FileReader();
  // reader.onload = function(e) {
  //   sentIdx = 0;
  //   frames = [];
  //   var buffer =  e.target.result;
  //   var chunks = [], i = 0, n = buffer.byteLength;
  //   while (i < n) {
  //     chunks.push(buffer.slice(i, i += chunkSize));
  //   }
  //   console.log('ArrayBuffer (chunks):', chunks.length, chunks);
  //   chunks.forEach(function(chunk, i) {
  //     var view = new Uint8Array(chunk);
  //     // var isFIN = i == chunks.length - 1;
  //     // if (isFIN) {
  //     //   console.log('FIN: Yes');
  //     //   view[0] = 0x80;
  //     // } else {
  //     //   console.log('FIN: No');
  //     //   view[0] = 0x01;
  //     // }
  //     // console.log('ArrayBuffer (Modified first byte):', view.buffer);
  //     frames.push(view.buffer);
  //   });
  //   sendFrame();
  // };
  // reader.readAsArrayBuffer(blob);
}
document.querySelector('input[name="send"]').addEventListener('click', function(e) {
  send()
});

function sendFrame() {
  if (sentIdx < frames.length) {
    if (socket.bufferedAmount == 0) {
      console.log('sending frame:', sentIdx);
      var view = frames[sentIdx];
      // socket.send(view);
      var reader = new FileReader();
      reader.onload = function(e) {
        socket.send(e.target.result);
        sentIdx++;
      };
      reader.readAsBinaryString(new Blob([ view ], { type: 'application/octet-stream' }));
    }
    setTimeout(sendFrame, 100);
  } else {
    console.log('done!');
  }
}
