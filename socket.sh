#!/bin/bash

HOSTNAME='localhost.localstack.cloud'
ENDPOINT="https://$HOSTNAME"
REGION="us-east-2" # matches default profile
LAMBDA_BUCKET="lambda-bucket"
LOCALSTACK_LOG="localstack.log"

BLUE='\033[1;36m'
RED='\033[1;31m'
GRAY='\033[0;37m'
NC='\033[0m'

usage()
{
cat << EOF
usage: $0 [-r|--recreate]

LocalStack Lambda/MWebSocket Test Tool

OPTIONS:
-r|--recreate           Stop and remove containers and/or volumes before starting again
-c|--clean              Stop and remove all test containers and volumes
-h|--help               Usage guide

EOF
}

clean()
{
    if [[ "$( docker container inspect -f '{{.State.Status}}' test-localstack )" == "running" ]]
    then
        docker-compose down --remove-orphans
    fi
}

RECREATE=''
while [ ! $# -eq 0 ]
do
    case "$1" in
        -r | --recreate)
            RECREATE='yes'
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

echo -e "${BLUE}${step}. Create S3 Bucket if not exists ...${NC}"
let "step=step+1"
if [[ -z $(aws --endpoint-url=$ENDPOINT s3api list-buckets --query "Buckets[?Name==\`$LAMBDA_BUCKET\`]" --output text) ]]
then
    aws --endpoint-url=$ENDPOINT s3 mb s3://$LAMBDA_BUCKET
else
    echo $LAMBDA_BUCKET
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

echo -e "${BLUE}${step}. Deploy Lambda WebSocket ...${NC}"
let "step=step+1"
npm run deploy-socket

echo
echo
echo -e "Now observe LocalStack logs around ${RED}InvocationException${NC}, ${RED}NoSuchKey${NC}, and ${RED}Unable to fetch CF custom resource result from s3${NC}!"
echo -e "${GRAY}docker container logs --follow test-localstack${NC}"
exit 1

echo -e "${GRAY}Waiting for Lambda to be ready ...${NC}"
let "sec=5"
while [ $sec -ge 0 ]
do
    echo -ne "\\rContinue in $sec seconds ..."
    let "sec=sec-1"
    sleep 1
done
echo

GATEWAY_SOCKET=$(aws --endpoint-url=$ENDPOINT apigatewayv2 get-apis --query 'Items[?Name==`lambda-socket-local`]' --output json | grep "ApiEndpoint" | sed -r 's/^[^:]*:(.*),$/\1/' | xargs | sed 's/localhost/localhost.localstack.cloud/g' | sed 's/ws:/wss:/g')

if [ -n $GATEWAY_SOCKET ]
then
  echo -e "${BLUE}${step}. Testing Lambda WebSocket ...${NC}"
  let "step=step+1"
  echo -e "${GRAY}wscat -c $GATEWAY_SOCKET${NC}"
  echo -e "${GRAY}Test Message: {\"action\": \"\$default\", \"data\": {\"test\":\"ok\"}}${NC}"
  echo -e "${GRAY}After receiving a successful response: {\"message\":\"ok\"}, close socket conenction to continue the test case: Ctrl+C${NC}"
  wscat -c $GATEWAY_SOCKET
else
  echo -e "${RED}Unable to fetch socket endpoint!${NC}"
  exit 1
fi
echo

echo -e "${GRAY}Waiting for WebSocket to be closed ...${NC}"
let "sec=5"
while [ $sec -ge 0 ]
do
    echo -ne "\\rContinue in $sec seconds ..."
    let "sec=sec-1"
    sleep 1
done
echo

echo -e "${BLUE}${step}. Re-deploy Lambda WebSocket ...${NC}"
let "step=step+1"
npm run deploy-socket
echo
echo
echo -e "Now re-deploy Lambda in a separate shell and observe LocalStack logs around ${RED}KeyError${NC}!"
echo -e "${GRAY}docker container logs --follow test-localstack${NC}"
