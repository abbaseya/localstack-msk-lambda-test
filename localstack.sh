#!/bin/bash

ENDPOINT="https://localhost.localstack.cloud"
REGION="us-east-2" # matches default profile
LAMBDA_BUCKET="lambda-bucket"
LAMBDA_TOPIC_PREFIX="lambda_data"
LAMBDA_TOPIC="${LAMBDA_TOPIC_PREFIX}_0"
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

usage()
{
cat << EOF
usage: $0 [-r|--recreate] [-m|--use-msk]

LocalStack Lambda/MSK Test Tool

OPTIONS:
-r|--recreate           Stop and remove containers and/or volumes before starting again
-k|--use-kafka          Use self-managaed Kafka instead of MSK
-z|--use-zookeeper      Fetch ZookeeperConnectString instead of BootstrapBrokerString
-f|--force-host         Use Host IP for MSK instead of LOCALSTACK_HOSTNAME
-g|--force-gateway      Use Docker Gateway IP for MSK instead of LOCALSTACK_HOSTNAME
-c|--clean              Stop and remove all test containers and volumes
-h|--help               Usage guide

EOF
}

clean()
{
    if [[ "$( docker container inspect -f '{{.State.Status}}' test-kafka )" == "running" ]]
    then
        docker-compose -f docker-compose-kafka.yml down --remove-orphans
        docker volume rm test-kafka-data
        docker volume rm test-zookeeper-conf
        docker volume rm test-zookeeper-data
    fi
    if [[ "$( docker container inspect -f '{{.State.Status}}' test-localstack )" == "running" ]]
    then
        docker-compose down --remove-orphans
    fi
}

RECREATE=''
USE_MSK='yes'
USE_ZOOKEEPER=''
USE_HOST=''
USE_GATEWAY=''
while [ ! $# -eq 0 ]
do
    case "$1" in
        -r | --recreate)
            RECREATE='yes'
            ;;
        -k | --use-kafka)
            USE_MSK=''
            ;;
        -z | --use-zookeeper)
            USE_ZOOKEEPER='yes'
            ;;
        -f | --force-host)
            USE_HOST='yes'
            ;;
        -g | --force-gateway)
            USE_GATEWAY='yes'
            ;;
        -c | --clean)
            clean
            exit
            ;;
        -h | --help)
            usage
            exit
            ;;
    esac
    shift
done

if [[ "$RECREATE" != '' ]]
then
    clean
fi

case "$OSTYPE" in
    darwin*)
        [ -f /private$TMPDIR/server.test.pem ] && rm /private$TMPDIR/server.test.pem*
        [ -f /private$TMPDIR/server.test.pem ] && rm /private$TMPDIR/zipfile.*
        TMPDIR=/private$TMPDIR docker-compose up -d
        ;;
    *)
        [ -f $TMPDIR/server.test.pem ] && rm $TMPDIR/server.test.pem*
        [ -f $TMPDIR/server.test.pem ] && rm $TMPDIR/zipfile.*
        docker-compose up -d
        ;;
esac

until curl --silent http://localhost:4566 | grep "\"status\": \"running\"" > /dev/null
do
    echo -ne "\\rWaiting for LocalStack to be ready ..."
done
echo

let "step=1"
echo -e "${BLUE}${step}. Set Region ...${NC}"
let "step=step+1"
echo $REGION
sed -ri -e 's!REGION=.*$!REGION='"$REGION"'!g' .env.local
[ -f '.env.local-e' ] && rm .env.local-e
echo
if [[ "$USE_MSK" != '' ]]
then
    echo -e "${BLUE}${step}. Set Cluster ARN ...${NC}"
    let "step=step+1"
    echo $CLUSTER_ARN
    sed -ri -e 's!CLUSTER_ARN=.*$!CLUSTER_ARN='"$CLUSTER_ARN"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e 
    echo
fi
echo -e "${BLUE}${step}. Create S3 Bucket if not exists ...${NC}"
let "step=step+1"
if [[ -z $(aws --endpoint-url=$ENDPOINT s3api list-buckets --query "Buckets[?Name==\`$LAMBDA_BUCKET\`]" --output text) ]]
then
    aws --endpoint-url=$ENDPOINT s3 mb s3://$LAMBDA_BUCKET
else
    echo $LAMBDA_BUCKET
fi
echo
HOST_IP=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
if [[ -z $HOST_IP ]]
then
    echo -e "${RED}Unable to fetch Host IP!${NC}"
    exit 1
fi
GATEWAY_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.Gateway}}{{end}}' test-localstack)
if [[ -z $GATEWAY_IP ]]
then
    echo -e "${RED}Unable to fetch Gateway IP!${NC}"
    exit 1
fi
if [[ "$USE_MSK" != '' ]]
then
    echo -e "${BLUE}${step}. Create MSK Config if not exists ...${NC}"
    let "step=step+1"
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
    echo -e "${BLUE}${step}. Create Kafka Cluster if not exists ...${NC}"
    let "step=step+1"
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
    if [[ "$RECREATE" != '' ]]
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
    echo -e "${BLUE}${step}. Fetch Kafka Broker ARN ...${NC}"
    let "step=step+1"
    if [[ "$USE_ZOOKEEPER" != '' ]]
    then
        echo -e "${GRAY}@whummer mentioned that the endpoint returned from DescribeCluster (localhost:4511) is in fact the Kafka Broker URL, not the Zookeeper URL${NC}"
        KAFKA_BROKER=$(aws --endpoint-url=$ENDPOINT kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.ZookeeperConnectString" | sed -r 's/"(.*)"/\1/g')
    else
        # echo -e "${GRAY}get-bootstrap-brokers does not return anything (only using --debug returns the BootstrapBrokerString and only using https://localhost.localstack.cloud not http://localhost:4566)${NC}"
        # aws --endpoint-url=$ENDPOINT kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --debug > $LOCALSTACK_LOG 2>&1
        # KAFKA_BROKER=$(cat $LOCALSTACK_LOG | grep "BootstrapBrokerString" | sed -r 's/[^:]*:"(.*)"\}\\n/\1/g' | sed 's/.$//')
        echo -e "${GRAY}UPDATE: The latest LocalStack image now returns the BootstrapBrokerString on get-bootstrap-brokers${NC}"
        if [[ "$USE_HOST" != '' ]]
        then
            KAFKA_BROKER=$(aws --endpoint-url=$ENDPOINT kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --query "BootstrapBrokerString" | sed -r 's/"(.*)"/\1/g' | sed 's/localhost/'"$HOST_IP"'/g')
        elif [[ "$USE_GATEWAY" != '' ]]
        then
            KAFKA_BROKER=$(aws --endpoint-url=$ENDPOINT kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --query "BootstrapBrokerString" | sed -r 's/"(.*)"/\1/g' | sed 's/localhost/'"$GATEWAY_IP"'/g')
        else
            KAFKA_BROKER=$(aws --endpoint-url=$ENDPOINT kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --query "BootstrapBrokerString" | sed -r 's/"(.*)"/\1/g')
        fi
    fi

    if [[ -n $KAFKA_BROKER ]]
    then
        echo $KAFKA_BROKER
        sed -ri -e 's!KAFKA_BROKER=.*$!KAFKA_BROKER='"$KAFKA_BROKER"'!g' .env.local
        [ -f '.env.local-e' ] && rm .env.local-e
        if [[ "$USE_HOST" != '' ]]
        then
            echo -e "${GRAY}NOTE: MSK still returning ${RED}ECONNREFUSED${GRAY} on \"localhost:XXXX\" during testing, while we explicitly set the brokerUrl to \"$HOST_IP:XXXX\"!${NC}"
        elif [[ "$USE_GATEWAY" != '' ]]
        then
            echo -e "${GRAY}NOTE: MSK still returning ${RED}NoBrokersAvailable${GRAY} on \"localhost:XXXX\" during testing, while we explicitly set the brokerUrl to \"$GATEWAY_IP:XXXX\"!${NC}"
        else
            echo -e "${GRAY}NOTE: MSK still returning ${RED}ECONNREFUSED${GRAY} on \"localhost:XXXX\" during testing!${NC}"
        fi
    else
        if [[ "$USE_ZOOKEEPER" != '' ]]
        then
            echo "${RED}Unable to fetch ZookeeperConnectString. Consider waiting a bit more!${NC}"
        else
            echo -e "${RED}Unable to fetch BootstrapBrokerString. Consider waiting a bit more!${NC}"
        fi
        exit 1
    fi
else
    echo -e "${BLUE}${step}. Fetch self-managed Kafka Broker ...${NC}"
    let "step=step+1"
    echo -e "${GRAY}Kafka suggests using Host IP: https://github.com/wurstmeister/kafka-docker/wiki/Connectivity${NC}"
    if ! grep -q 'HOST_IP' .env
    then
        echo -e "\\nHOST_IP=$HOST_IP" >> .env
    else
        sed -ri -e 's!HOST_IP=.*$!HOST_IP='"$HOST_IP"'!g' .env
        [ -f '.env-e' ] && rm .env-e
    fi
    KAFKA_BROKER="$HOST_IP:9092"
    echo $KAFKA_BROKER
    sed -ri -e 's!KAFKA_BROKER=.*$!KAFKA_BROKER='"$KAFKA_BROKER"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
    echo -e "${GRAY}UPDATE: The latest LocalStack image does translate --self-managed-event-source by serverless properly, but the event itself does not get dispatched when producing a message to Kafka broker!${NC}"
fi
echo
echo -e "${BLUE}${step}. Create LocalStack Secret ...${NC}"
let "step=step+1"
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
echo -e "${BLUE}${step}. Fetch Security Groups from LocalStack ...${NC}"
let "step=step+1"
read -r -d '' -a SECURITY_GROUPS < <( aws --endpoint-url=$ENDPOINT ec2 describe-security-groups --query "SecurityGroups[].[GroupId]" --output text )
for i in "${!SECURITY_GROUPS[@]}"
do
    echo ${SECURITY_GROUPS[i]}
    # Set environment for Lambda
    sed -ri -e 's!SECURITY_GROUP'"$((${i}+1))"'=.*$!SECURITY_GROUP'"$((${i}+1))"'='"${SECURITY_GROUPS[i]}"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
done
echo
echo -e "${BLUE}${step}. Fetch VPC Subnets from LocalStack ...${NC}"
let "step=step+1"
read -r -d '' -a VPC_SUBNESTS < <( aws --endpoint-url=$ENDPOINT ec2 describe-subnets --query "Subnets[].[SubnetId]" --output text )
for i in "${!VPC_SUBNESTS[@]}"
do
    echo ${VPC_SUBNESTS[i]}
    # Set environment for Lambda
    sed -ri -e 's!VPC_SUBNET'"$((${i}+1))"'=.*$!VPC_SUBNET'"$((${i}+1))"'='"${VPC_SUBNESTS[i]}"'!g' .env.local
    [ -f '.env.local-e' ] && rm .env.local-e
done
echo
echo -e "${BLUE}${step}. Install Node Dependencies if not already installed ...${NC}"
let "step=step+1"
[ ! -d 'node_modules' ] && npm install
cd layer-basic/nodejs
[ ! -d 'node_modules' ] && npm install
cd ../../
echo
if [[ "$USE_MSK" != '' ]]
then
    echo -e "${BLUE}${step}. Deploy Lambda MSK ...${NC}"
    let "step=step+1"
    npm run deploy-event-msk

    echo -e "${GRAY}Waiting for Lambda MSK to be ready ...${NC}"
    let "sec=5"
    while [ $sec -ge 0 ]
    do
        echo -ne "\\rContinue in $sec seconds ..."
        let "sec=sec-1"
        sleep 1
    done
    echo
else
    if [[ "$RECREATE" != '' ]]
    then
        if ! grep -q 'LAMBDA_TOPIC' .env
        then
            echo -e "\\nLAMBDA_TOPIC=$LAMBDA_TOPIC" >> .env
        else
            sed -ri -e 's!LAMBDA_TOPIC=.*$!LAMBDA_TOPIC='"$LAMBDA_TOPIC"'!g' .env
            [ -f '.env-e' ] && rm .env-e
        fi
        echo -e "${BLUE}${step}. Starting self-managed Kafka on port 9092 ...${NC}"
        let "step=step+1"
        docker-compose -f docker-compose-kafka.yml up -d
        echo
    fi
    echo -e "${BLUE}${step}. Deploy Lambda Kafka ...${NC}"
    let "step=step+1"
    npm run deploy-event-kafka

    echo -e "${GRAY}Waiting for Lambda Kafka to be ready ...${NC}"
    let "sec=5"
    while [ $sec -ge 0 ]
    do
        echo -ne "\\rContinue in $sec seconds ..."
        let "sec=sec-1"
        sleep 1
    done
    echo
    echo
    echo -e "${GRAY}The latest LocalStack does seem to translate --self-managed-event-source by serverless, but the event itself does ${RED}not${GRAY} get dispatched wgen producing a message to Kafka broker!${NC}"
    # echo -e "${BLUE}${step}. Manually map topics from Lambda to Kafka ..."
    # echo -e "${GRAY}LocalStack does not seem to translate --self-managed-event-source by serverless${NC}"
    # echo -e "${GRAY}Issue addressed at https://github.com/localstack/localstack/issues/4569${NC}"
    # FUNC_ARN=$(aws --endpoint-url=$ENDPOINT lambda list-functions --query "Functions[?FunctionName==\`lambda-process-local-processDataTopic0\`].FunctionArn" --output text)
    # if [[ -n $FUNC_ARN ]]
    # then
    #     sed -ri -e 's!LAMBDA_TOPIC_PREFIX=.*$!LAMBDA_TOPIC_PREFIX='"$LAMBDA_TOPIC_PREFIX"'!g' .env.local
    #     sed -ri -e 's!LAMBDA_TOPIC=.*$!LAMBDA_TOPIC='"$LAMBDA_TOPIC"'!g' .env.local
    #     [ -f '.env.local-e' ] && rm .env.local-e
    #     echo "create-event-source-mapping: \"$LAMBDA_TOPIC\""
    #     aws --endpoint-url=$ENDPOINT lambda create-event-source-mapping \
    #         --topics $LAMBDA_TOPIC \
    #         --source-access-configuration Type=SASL_SCRAM_512_AUTH,URI=$SECRET_ARN \
    #         --function-name $FUNC_ARN \
    #         --self-managed-event-source "{\"Endpoints\":{\"KAFKA_BOOTSTRAP_SERVERS\":[\"$HOST_IP:9092\"]}}" \
    #         &>/dev/null # LocalStack opens output in text editor which breaks the loop!
    # else
    #     echo -e "${RED}Unable to create event source map for Kafka topic: \"$LAMBDA_TOPIC\"${NC}"
    #     echo -e "${RED}The following Lambda ARN is missing: \"$FUNC_ARN\"${NC}"
    #     exit 1
    # fi
fi
echo
echo -e "${BLUE}${step}. Deploy Lambda HTTP ...${NC}"
let "step=step+1"
npm run deploy-http

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
echo -e "${BLUE}${step}. Testing Lambda HTTP ...${NC}"
let "step=step+1"
echo -e "${GRAY}curl -X POST -d '{\"message\":\"test\"}' $LAMBDA_ENDPOINT/test/post${NC}"
curl -X POST -d '{"message":"test"}' $LAMBDA_ENDPOINT/test/post
echo
echo
echo -e "Now observe LocalStack logs around ${RED}ECONNREFUSED${NC}, ${RED}KafkaJSConnectionClosedError${NC}, ${RED}EventSourceArn${NC}, ${RED}[BrokerPool] Closed connection${NC}, or ${RED}There is no leader for this topic-partition as we are in the middle of a leadership election${NC}!"
echo -e "${GRAY}docker container logs --follow test-localstack${NC}"
