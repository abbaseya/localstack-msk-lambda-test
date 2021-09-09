'use strict';

let processDataTopic = async (event, context) => {
    try {
        console.log('Received an event from Kafka:', event);
    } catch (e) {
        console.log('lambda-process -> processDataTopic -> error', e);
        return false;
    }
    return true;
}

module.exports.processDataTopic = processDataTopic;
