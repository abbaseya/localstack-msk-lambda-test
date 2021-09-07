let _ = require('lodash');
const {Kafka,CompressionTypes} = require('kafkajs');

const ContentHelper = {
    MAX_SQS_ITEM_BYTE_SIZE: 256000,

    pushToQueue: async function (receivedData) {
        let dataContainer = _.cloneDeep(receivedData);
        dataContainer.micro_time_added = new Date().getTime();
        dataContainer.collection = 'content';

        try {
            return await this.sendCompressed(dataContainer);
        } catch (error) {
            console.log(error);
            return null;
        }
    },
    sendCompressed: async function (chunkContainer) {
        let chunkString = JSON.stringify(chunkContainer),
            topicIndex = (chunkContainer.micro_time_added % 10).toString(),
            brokersUrl = process.env.KAFKA_BROKER.replace('localhost', process.env.LOCALSTACK_HOSTNAME),
            topicName = process.env.KAFKA_DATA_TOPIC_PREFIX + '_' + topicIndex;
        
        console.log('brokersUrl:', brokersUrl);
        const client = new Kafka({
            clientId: 'default',
            brokers: brokersUrl.split(',')
        });
        const producer = client.producer();
        await producer.connect();
        await producer.send({
            topic: topicName,
            compression: CompressionTypes.GZIP,
            messages: [{
                value: chunkString
            }]
        })
    }
};

module.exports = ContentHelper;
