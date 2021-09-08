#!/bin/bash

ENDPOINT="https://localhost.localstack.cloud"
REGION="us-east-2" # matches default profile
LAMBDA_BUCKET="lambda-bucket"
KAFKA_VERSION="2.5.0"
CLUSTER_NAME="msk-cluster"
CLUSTER_INFO="cluster-info.json"
CLUSTER_ARN="arn:aws:kafka:$REGION:000000000000:cluster/$CLUSTER_NAME"
MSK_NAME="MSKConfiguration"
MSK_CONFIGURATION="msk.txt"
MSK_ARN="arn:aws:kafka:$REGION:000000000000:configuration/$MSK_NAME"
SECRET_NAME=test
LOCALSTACK_LOG="localstack.log"


BLUE='\033[1;36m'
RED='\033[1;31m'
GRAY='\033[0;37m'
NC='\033[0m'

if [[ "$1" == "--recreate" && "$( docker container inspect -f '{{.State.Status}}' test-localstack )" == "running" ]]
then
    docker-compose down
fi

docker-compose up -d

until curl --silent http://localhost:4566 | grep "\"status\": \"running\"" > /dev/null
do
    echo -ne "\\rWaiting for LocalStack to be ready ..."
done
echo

echo -e "${BLUE}1. Set Region ...${NC}"
echo $REGION
sed -ri -e 's!REGION=.*$!REGION='"$REGION"'!g' .env.local
[ -f '.env.local-e' ] && rm .env.local-e
echo
echo -e "${BLUE}2. Set Cluster ARN ...${NC}"
echo $CLUSTER_ARN
sed -ri -e 's!CLUSTER_ARN=.*$!CLUSTER_ARN='"$CLUSTER_ARN"'!g' .env.local
[ -f '.env.local-e' ] && rm .env.local-e 
echo
echo -e "${BLUE}3. Create S3 Bucket if not exists ...${NC}"
if [[ -z $(aws --endpoint-url=$ENDPOINT s3api list-buckets --query "Buckets[?Name==\`$LAMBDA_BUCKET\`]" --output text) ]]
then
    aws --endpoint-url=$ENDPOINT s3 mb s3://$LAMBDA_BUCKET
else
    echo $LAMBDA_BUCKET
fi
echo
echo -e "${BLUE}4. Create MSK Config if not exists ...${NC}"
aws --endpoint-url=$ENDPOINT kafka describe-configuration --arn $MSK_ARN > $LOCALSTACK_LOG 2>&1
state=$(cat $LOCALSTACK_LOG | grep "NotFoundException")
if [[ -n "$state" ]]
then
    cat > ${MSK_CONFIGURATION} <<EOM
auto.create.topics.enable = true
zookeeper.connection.timeout.ms = 2000
log.roll.ms = 604800000
EOM
    aws --endpoint-url=$ENDPOINT kafka create-configuration --name $MSK_NAME --server-properties file://$MSK_CONFIGURATION > $LOCALSTACK_LOG 2>&1
fi
cat $LOCALSTACK_LOG
echo
echo -e "${BLUE}5. Create Kafka Cluster if not exists ...${NC}"
aws --endpoint-url=$ENDPOINT kafka describe-cluster --cluster-arn $CLUSTER_ARN > $LOCALSTACK_LOG 2>&1
state=$(cat $LOCALSTACK_LOG | grep "ClusterNotFoundError")
if [ -n "$state" ]
then
    SUBNESTS=$(aws --endpoint-url=$ENDPOINT ec2 describe-subnets --query "Subnets[*].SubnetId")
    SECURITY_GROUPS=$(aws --endpoint-url=$ENDPOINT ec2 describe-security-groups --query "SecurityGroups[*].GroupId")
    cat > ${CLUSTER_INFO} <<EOM
{
    "BrokerNodeGroupInfo": {
        "BrokerAZDistribution": "DEFAULT",
        "InstanceType": "kafka.m5.large",
        "ClientSubnets": $SUBNESTS,
        "SecurityGroups": $SECURITY_GROUPS,
        "StorageInfo": {
            "EbsStorageInfo": {
                "VolumeSize": 80
            }
        }
    },
    "ClusterName": "$CLUSTER_NAME",
    "ConfigurationInfo": {
        "Arn": "$MSK_ARN",
        "Revision": 1
    },
    "EncryptionInfo": {
        "EncryptionAtRest": {
            "DataVolumeKMSKeyId": ""
        },
        "EncryptionInTransit": {
            "ClientBroker": "PLAINTEXT",
            "InCluster": false
        }
    },
    "EnhancedMonitoring": "PER_BROKER",
    "KafkaVersion": "$KAFKA_VERSION",
    "NumberOfBrokerNodes": 1,
    "OpenMonitoring": {
        "Prometheus": {
            "JmxExporter": {
                "EnabledInBroker": false
            },
            "NodeExporter": {
                "EnabledInBroker": false
            }
        }
    },
    "LoggingInfo": {
        "BrokerLogs": {
            "CloudWatchLogs": {
                "Enabled": false
            },
            "Firehose": {
                "Enabled": false
            },
            "S3": {
                "Enabled": false
            }
        }
    }
}
EOM
    aws --endpoint-url=$ENDPOINT kafka create-cluster --cli-input-json file://$CLUSTER_INFO
else
    cat $LOCALSTACK_LOG
fi
echo
if [[ "$1" == "--recreate" ]]
then
    until docker container logs test-localstack | grep -E "Starting local Zookeeper/Kafka brokers on ports" > /dev/null
    do
        echo -ne "\\rWaiting for Zookeeper/Kafka to be ready ..."
    done
    echo
    echo -e "${GRAY}Nothing in LocalStack logs indicating that Zookeeper/Kafka are ready to accept connections, so we wait a little more ...${NC}"
    let "sec=15"
    while [ $sec -ge 0 ]
    do
        echo -ne "\\rContinue in $sec seconds ..."
        let "sec=sec-1"
        sleep 1
    done
    echo
fi
echo
echo -e "${BLUE}6. Fetch Kafka Broker ARN ...${NC}"

# TODO: get-bootstrap-brokers does not return anything (only using --debug returns the BootstrapBrokerString and only using https://localhost.localstack.cloud not http://localhost:4566)
aws --endpoint-url=$ENDPOINT kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --debug > $LOCALSTACK_LOG 2>&1
KAFKA_BROKER=$(cat $LOCALSTACK_LOG | grep "BootstrapBrokerString" | sed -r 's/[^:]*:"(.*)"\}\\n/\1/g' | sed 's/.$//')

# HINT: @whummer mentioned that the endpoint returned from DescribeCluster (localhost:4511) is in fact the Kafka Broker URL, not the Zookeeper URL!
# KAFKA_BROKER=$(aws --endpoint-url=$ENDPOINT kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.ZookeeperConnectString" | sed -r 's/"(.*)"/\1/g')

if [[ -n $KAFKA_BROKER ]]
then
    echo $KAFKA_BROKER
    sed -ri -e 's!KAFKA_BROKER=.*$!KAFKA_BROKER='"$KAFKA_BROKER"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
else
    echo -e "${RED}Unable to fetch BootstrapBrokerString. Consider waiting a bit more!${NC}"
    # echo "Unable to fetch ZookeeperConnectString. Consider waiting a bit more!"
    exit 1
fi
echo
echo -e "${BLUE}7. Create LocalStack Secret ...${NC}"
SECRET_ARN=''
setsecret()
{
    SECRET_ARN=$(aws --endpoint-url=$ENDPOINT secretsmanager list-secrets --query "SecretList[?Name==\`$SECRET_NAME\`].ARN" --output text)
}
NEW_SECRET=''
setsecret
if [[ -z $SECRET_ARN ]]
then
    NEW_SECRET='yes'
    aws --endpoint-url=$ENDPOINT secretsmanager create-secret --name $SECRET_NAME
    setsecret
fi
if [[ -n $SECRET_ARN ]]
then
    [ "$NEW_SECRET" == '' ] && echo $SECRET_ARN
    sed -ri -e 's!SECRET_ARN=.*$!SECRET_ARN='"$SECRET_ARN"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
else
    echo -e "${RED}Unable to fetch SecretList ARN. Consider waiting a bit more!${NC}"
    exit 1
fi
echo
echo -e "${BLUE}8. Fetch Security Groups from LocalStack ...${NC}"
read -r -d '' -a SECURITY_GROUPS < <( aws --endpoint-url=$ENDPOINT ec2 describe-security-groups --query "SecurityGroups[].[GroupId]" --output text )
for i in "${!SECURITY_GROUPS[@]}"
do
    echo ${SECURITY_GROUPS[i]}
    # Set environment for Lambda
    sed -ri -e 's!SECURITY_GROUP'"$((${i}+1))"'=.*$!SECURITY_GROUP'"$((${i}+1))"'='"${SECURITY_GROUPS[i]}"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
done
echo
echo -e "${BLUE}9. Fetch VPC Subnets from LocalStack ...${NC}"
read -r -d '' -a VPC_SUBNESTS < <( aws --endpoint-url=$ENDPOINT ec2 describe-subnets --query "Subnets[].[SubnetId]" --output text )
for i in "${!VPC_SUBNESTS[@]}"
do
    echo ${VPC_SUBNESTS[i]}
    # Set environment for Lambda
    sed -ri -e 's!VPC_SUBNET'"$((${i}+1))"'=.*$!VPC_SUBNET'"$((${i}+1))"'='"${VPC_SUBNESTS[i]}"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
done
echo
echo -e "${BLUE}10. Install Node Dependencies if not already installed ...${NC}"
[ ! -d 'node_modules' ] && npm install
cd layer-basic/nodejs
[ ! -d 'node_modules' ] && npm install
cd ../../
echo
echo -e "${BLUE}11. Deploy Lambda HTTP ...${NC}"
npm run deploy

echo -e "${GRAY}Waiting for Lambda to be ready ...${NC}"
let "sec=5"
while [ $sec -ge 0 ]
do
    echo -ne "\\rContinue in $sec seconds ..."
    let "sec=sec-1"
    sleep 1
done
echo

LAMBDA_ENDPOINT=$ENDPOINT/restapis/$(aws --endpoint-url=$ENDPOINT apigateway get-rest-apis --query 'items[?name==`lambda-http-local`]' --output json | grep "id" | sed -r 's/^[^:]*:(.*),$/\1/' | xargs)/local/_user_request_
echo
echo -e "${BLUE}12. Testing Lambda HTTP ...${NC}"
curl -X POST -d "{\"message\":\"test\"}" $LAMBDA_ENDPOINT/test/post
echo
echo
echo -e "${BLUE}13. Deploy Lambda EVENT ...${NC}"
npm run deploy-event

echo -e "${GRAY}Waiting for Lambda EVENT to be ready ...${NC}"
let "sec=5"
while [ $sec -ge 0 ]
do
    echo -ne "\\rContinue in $sec seconds ..."
    let "sec=sec-1"
    sleep 1
done
echo
echo
echo -e "Now observe LocalStack logs around ${RED}ECONNREFUSED${NC}, ${RED}KafkaJSConnectionClosedError${NC}, or ${RED}EventSourceArn${NC}!"
echo -e "${GRAY}docker container logs --follow test-localstack${NC}"
