#!/usr/bin/env bash

CONFIG=$(<configuration.json)

SG_NAME=`echo $CONFIG | jq '."security-group-name"' | tr -d '"'`
BUCKET_NAME=`echo $CONFIG | jq '."s3-bucket-name"' | tr -d '"'`
ROLE_NAME=`echo $CONFIG | jq '."role-name"' | tr -d '"'`
KEY_VALUE_PAIR=`echo $CONFIG | jq '."key-name"' | tr -d '"'`
SUBNET_ID=`echo $CONFIG | jq '."subnet-id"' | tr -d '"'`
AVAILABILITY_ZONE=`echo $CONFIG | jq '."availability-zone"' | tr -d '"'`
REGION=`echo $CONFIG | jq '."region"' | tr -d '"'`
MASTER_NODE_COUNT=`echo $CONFIG | jq '."master-node-count"' | tr -d '"'`
DATA_NODE_COUNT=`echo $CONFIG | jq '."data-node-count"' | tr -d '"'`
NAME=`echo $CONFIG | jq '."name"' | tr -d '"'`
IMAGE_NAME=`echo $CONFIG | jq '."target-image-name"' | tr -d '"'`
TAGS=`echo $CONFIG | jq '."tags"' | tr -d '"'`


sed  -e "s/my-region/${REGION}/g" -e "s/my-bucket/${BUCKET_NAME}/g" -e "s/my_cluster_name/${NAME}/g" ./04-runtime.data.userdata.txt | tee ./runtime.data.userdata.txt
sed  -e "s/my-region/${REGION}/g" -e "s/my-bucket/${BUCKET_NAME}/g" -e "s/my_cluster_name/${NAME}/g" ./04-runtime.master.userdata.txt | tee ./runtime.master.userdata.txt

SECURITY_GROUPS=`echo $(aws ec2 describe-security-groups --filters Name=group-name,Values=${SG_NAME})`

SECURITY_GROUP_ID=`echo $SECURITY_GROUPS | jq '.SecurityGroups[0].GroupId' | tr -d '"'`

AMIS=`echo $(aws ec2 describe-images --filters "Name=tag:Name,Values=${IMAGE_NAME}")`

BASE_IMAGE_ID=`echo $AMIS | jq '.Images[0].ImageId' | tr -d '"'`

echo "Using base id ${BASE_IMAGE_ID}"

echo "Creating the data instances"

COUNTER=0
while [ $COUNTER -lt ${DATA_NODE_COUNT} ]; do
    let INDEX=$((COUNTER+1))

    INSTANCES=`echo $(aws ec2 run-instances --image-id ${BASE_IMAGE_ID} \
      --count 1 \
      --instance-type t2.xlarge \
      --key-name ${KEY_VALUE_PAIR} \
      --subnet-id ${SUBNET_ID} \
      --block-device-mappings file://04-data-mapping.json  \
      --iam-instance-profile Name=${ROLE_NAME} \
      --user-data file://runtime.data.userdata.txt \
      --tag-specifications="ResourceType=instance,Tags=[${TAGS},{Key=Name,Value=${NAME}-data},{Key=Index,Value=${INDEX}}]" \
      --associate-public-ip-address \
      --security-group-ids ${SECURITY_GROUP_ID} | \
    jq -rc '.Instances[].InstanceId')`

    let COUNTER=COUNTER+1
done

echo "instances now running"

exit

echo "Creating the master instances"

COUNTER=0
while [ $COUNTER -lt ${MASTER_NODE_COUNT} ]; do
    let INDEX=$((COUNTER+1))

   INSTANCES=`echo $(aws ec2 run-instances --image-id ${BASE_IMAGE_ID} \
      --count 1 \
      --instance-type t2.xlarge \
      --key-name ${KEY_VALUE_PAIR} \
      --subnet-id ${SUBNET_ID} \
      --block-device-mappings file://04-master-mapping.json  \
      --iam-instance-profile Name=${ROLE_NAME} \
      --user-data file://runtime.master.userdata.txt \
      --tag-specifications="ResourceType=instance,Tags=[${TAGS},{Key=Name,Value=${NAME}-master},{Key=Index,Value=${INDEX}}]" \
      --associate-public-ip-address \
      --security-group-ids ${SECURITY_GROUP_ID} | \
    jq -rc '.Instances[].InstanceId')`

    let COUNTER=COUNTER+1
done

echo "Finished creating the instances for master"