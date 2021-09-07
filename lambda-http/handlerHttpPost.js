'use strict';

const HttpResponse = require("./HttpResponse");
const ContentHelper = require("./ContentHelper");

let handlePost = async (event, context) => {
    try {
        HttpResponse.currentEvent = event;

        if (event.httpMethod === 'OPTIONS') {
            return HttpResponse.handleResponse('ok', HttpResponse.statusCodes.ok);
        }

        if (event.body) {
            let data = HttpResponse.parseRequest(event, HttpResponse.resultTypeObject);

            if (data) {
                await ContentHelper.pushToQueue(data);
                try {
                    return HttpResponse.handleResponse('ok', HttpResponse.statusCodes.ok);
                } catch (e) {
                    return HttpResponse.handleResponse('handling error', HttpResponse.statusCodes.error, e);
                }
            }
        }

        return HttpResponse.handleResponse('', HttpResponse.statusCodes.error);
    } catch (e) {
        console.log(e);
        return HttpResponse.handleResponse('body error', HttpResponse.statusCodes.badRequest, e);
    }
};

module.exports.handlePost = handlePost;

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
