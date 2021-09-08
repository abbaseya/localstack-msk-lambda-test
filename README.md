# LocalStack Lambda/MSK Test

## Requirements

* Bash v3+
* Curl v7+
* AWS CLI v2+
* Serverless v2+
* Node.js v12+

## Instructions

1. Create `.env` with your LocalStack API Key: `LOCALSTACK_LICENSE=API_KEY`
2. Point `localhost.localstack.cloud` to `127.0.0.1` at your `/etc/hosts`
3. Modify `REGION` variable near the top of `localstack.sh` to match your AWS default profile
4. Run: `./localstack.sh`
    > To force creating a fresh container: `./localstack.sh --recreate`
5. Observe LocalStack tailed logs around `ECONNREFUSED`, `KafkaJSConnectionClosedError`, or `EventSourceArn`!
    ```
    docker container logs --follow test-localstack
    ```
6. Review comments in teh above script, as well as the generated files:
  * `cluster-info.json`
  * `localstack.log`
  * `msk.txt`

## Notes

1. Connection to Kafka happens around line 26 at `lambda-http/ContentHelper.js`
2. For testing `ZookeeperConnectString` instead, uncommend line 160 at `localstack.sh` and try again
