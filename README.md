# LocalStack Lambda/MSK Test

## UPDATES

- [x] Issue [#4544](https://github.com/localstack/localstack/issues/4544): **Partially Resolved** using the latest LocalStack docker image released on 15 Sep 2021 - Thanks to [@whummer](https://github.com/whummer) – Passed test using `./localstack.sh --use-hostname`, but the event does not get dispatched when subscribing to more than one Kafka topic (_see `processDataTopic1` at `serverless-event-msk.yml`_)
- [x] Issue [#4569](https://github.com/localstack/localstack/issues/4569): **Partially Resolved** using the latest LocalStack docker image released on 15 Sep 2021 - Thanks to [@whummer](https://github.com/whummer) - LocalStack now translates `--self-managed-event-source` by Serverless properly, but the event itself does not get dispatched when producing a message to Kafka Broker
- [ ] Issue [#4550](https://github.com/localstack/localstack/issues/4550): _Pending_
- [x] Issue [#4626](https://github.com/localstack/localstack/issues/4626): **Resolved** using the latest LocalStack docker image released on 22 Sep 2021 - Thanks to [@whummer](https://github.com/whummer) – Passed test using `./socket.sh`
- [x] Issue [#4606](https://github.com/localstack/localstack/issues/4606): **Resolved** using the latest LocalStack docker image released on 11 Oct 2021 - Thanks to [@whummer](https://github.com/whummer) – Passed test using `../localstack.sh --use-hostname`
- [ ] Issue [#4893](https://github.com/localstack/localstack/issues/4893)

## Requirements

* Bash v3+
* Curl v7+
* AWS CLI v2+
* Serverless v2+
* Node.js v12+
* WSCAT 5+

## Instructions

1. Create `.env` with your LocalStack API Key: `LOCALSTACK_LICENSE=API_KEY`
2. Point `localhost.localstack.cloud` to `127.0.0.1` at your `/etc/hosts`

### WebSocket

1. Modify `REGION` variable near the top of `socket.sh` to match your AWS default profile
2. Run: `./socket.sh`
    1. To force creating a fresh container: `./socket.sh --recreate`
3. Once connected to WebSocket, enter test message: `{"action": "\$default", "data": {"test":"ok"}}`
4. After receiving a successful response: `{"message":"ok"}`, close socket conenction to continue the test case: `Ctrl+C`
5. Observe LocalStack tailed logs around `KeyError`!
    ```
    docker container logs --follow test-localstack
    ```

### MSK/Kafka

1. Modify `REGION` variable near the top of `localstack.sh` to match your AWS default profile
2. Run: `./localstack.sh` (_detault test uses MSK_)
    1. To test self-managed Kafka: `./localstack.sh --use-kafka`
    2. To force creating a fresh container: `./localstack.sh --recreate`
3. Observe LocalStack tailed logs around `ECONNREFUSED`, `KafkaJSConnectionClosedError`, `EventSourceArn`, `[BrokerPool] Closed connection`, or `There is no leader for this topic-partition as we are in the middle of a leadership election`!
    ```
    docker container logs --follow test-localstack
    ```
4. Review comments in teh above script, as well as the generated files:
  * `cluster-info.json`
  * `localstack.log`
  * `msk.txt`

## Notes

1. Connection to Kafka happens around line 26 at `lambda-http/ContentHelper.js`
2. For testing `ZookeeperConnectString` instead: `./localstack.sh --use-msk --use-zookeeper`
