const AWS = require('aws-sdk');
const HttpResponse = require("./HttpResponse");

let handleConnect = async (event, context) => {
    HttpResponse.currentEvent = event;
    return HttpResponse.handleResponse('Connected...', HttpResponse.statusCodes.ok);
};

let handleDisconnect = async (event, context) => {
    HttpResponse.currentEvent = event;
    return HttpResponse.handleResponse('Disconnected...', HttpResponse.statusCodes.ok);
};

let handleConnection = async (event, context) => {
    HttpResponse.currentEvent = event;
    let eventType = event.requestContext.eventType
    if (eventType === 'CONNECT') {
        return handleConnect(event, context);
    } else if (eventType === 'DISCONNECT') {
        return handleDisconnect(event, context);
    } else {
        return HttpResponse.handleResponse(eventType || "handleConnection", HttpResponse.statusCodes.ok);
    }
};

module.exports.handleConnect = handleConnect;
module.exports.handleDisconnect = handleDisconnect;
module.exports.handleConnection = handleConnection;


module.exports.auth = async (event, context) => {
    // return policy statement that allows to invoke the connect function.
    // in a real world application, you'd verify that the header in the event
    // object actually corresponds to a user, and return an appropriate statement accordingly
    return {
        "principalId": "user",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": event.methodArn
                }
            ]
        }
    };
};
/**
 *
 * @param {Object} event
 * @param {String} event.body = '{"action": "$default", "data": "{\"test\":\"ok\"}"}'
 * @param {Object} context
 * @return {Promise<{body: string, statusCode: number}>}
 */

let handleDefault = async (event, context) => {
    try {
        console.log('Received an event from socket:', event);

        return HttpResponse.handleResponse({
            message: 'ok',
        }, HttpResponse.statusCodes.ok);
    } catch (e) {
        console.log('lambda-socket -> handleDefault -> error', e);
        return HttpResponse.handleResponse('', HttpResponse.statusCodes.error, e);
    }
    return true;
}

module.exports.handleDefault = handleDefault;


function handleBuffer(body) {
    var buffer = Buffer.from(body, 'base64');
    console.log('Buffer:', buffer);
    const firstByte = buffer.readUInt8(0);
    const isFinalFrame = Boolean((firstByte >>> 7) & 0x1); 
    const [reserved1, reserved2, reserved3] = [ Boolean((firstByte >>> 6) & 0x1), Boolean((firstByte >>> 5) & 0x1), Boolean((firstByte >>> 4) & 0x1) ];
    const opCode = firstByte & 0xF;
    // We can return null to signify that this is a connection termination frame 
    if (opCode === 0x8) {
        return null;
    }
    // We only care about text frames from this point onward 
    if (opCode !== 0x1) {
        return;
    }
    const secondByte = buffer.readUInt8(1); 
    const isMasked = Boolean((secondByte >>> 7) & 0x1); 
    // Keep track of our current position as we advance through the buffer 
    let currentOffset = 2; let payloadLength = secondByte & 0x7F; 
    if (payloadLength > 125) { 
        if (payloadLength === 126) { 
            payloadLength = buffer.readUInt16BE(currentOffset); 
            currentOffset += 2; 
        } else { 
            // 127 
            // If this has a value, the frame size is ridiculously huge! 
            const leftPart = buffer.readUInt32BE(currentOffset); 
            const rightPart = buffer.readUInt32BE(currentOffset += 4); 
            // Honestly, if the frame length requires 64 bits, you're probably doing it wrong. 
            // In Node.js you'll require the BigInt type, or a special library to handle this. 
            throw new Error('Large payloads not currently implemented'); 
        } 
    }

    let maskingKey;
    if (isMasked) {
        maskingKey = buffer.readUInt32BE(currentOffset);
        currentOffset += 4;
    }

    // Allocate somewhere to store the final message data
    var data = Buffer.alloc(payloadLength);
    // Only unmask the data if the masking bit was set to 1
    if (isMasked) {
        // Loop through the source buffer one byte at a time, keeping track of which
        // byte in the masking key to use in the next XOR calculation
        for (let i = 0, j = 0; i < payloadLength; ++i, j = i % 4) {
        // Extract the correct byte mask from the masking key
            const shift = j == 3 ? 0 : (3 - j) << 3; 
            const mask = (shift == 0 ? maskingKey : (maskingKey >>> shift)) & 0xFF;
            // Read a byte from the source buffer 
            const source = buffer.readUInt8(currentOffset++); 
            // XOR the source byte and write the result to the data 
            buffer.data.writeUInt8(mask ^ source, i); 
        }
    } else {
        // Not masked - we can just read the data as-is
        buffer.copy(data, 0, currentOffset++);
    }

    return data.toString('utf8');
}