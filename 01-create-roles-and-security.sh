#!/usr/bin/env bash

CONFIG=$(<configuration.json)

SG_NAME=`echo $CONFIG | jq '."security-group-name"' | tr -d '"'`
BUCKET_NAME=`echo $CONFIG | jq '."s3-bucket-name"' | tr -d '"'`
ROLE_NAME=`echo $CONFIG | jq '."role-name"' | tr -d '"'`
VPC_ID=`echo $CONFIG | jq '."vpc-id"' | tr -d '"'`

MY_IP=`echo $(curl -s http://whatismyip.akamai.com/)`
VPC_IP=`echo $(aws ec2 describe-vpcs --vpc-ids ${VPC_ID} | jq '.Vpcs[0].CidrBlockAssociationSet[0].CidrBlock') | tr -d '"'`

echo "VPC internal id: ${VPC_IP}"
echo "Your external IP address : ${MY_IP}"

echo "*************** CREATING SECURITY GROUP ${SG_NAME} ***************"

SECURITY_GROUPS=`echo $(aws ec2 describe-security-groups --filters Name=group-name,Values=${SG_NAME})`


if [ `echo $SECURITY_GROUPS | jq '.SecurityGroups | length'` -eq 1 ]
then
  echo "Group exists...."

  SECURITY_GROUP_ID=`echo $SECURITY_GROUPS | jq '.SecurityGroups[0].GroupId' | tr -d '"'`
else
  echo "Group does not exist.. creating"

  TMP=`echo $(aws ec2 create-security-group --description 'elastic search development' --group-name=${SG_NAME} --vpc-id ${VPC_ID})`

  SECURITY_GROUP_ID=`echo $TMP | jq '.GroupId' | tr -d '"'`

  aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=${MY_IP}/32,Description='SSH access from my external IP'}]"
  aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions IpProtocol=tcp,FromPort=5601,ToPort=5601,IpRanges="[{CidrIp=${MY_IP}/32,Description='kibana access'}]"
  aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions IpProtocol=tcp,FromPort=5601,ToPort=5601,IpRanges="[{CidrIp=${VPC_IP},Description='ELB access for 5601'}]"
  aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions IpProtocol=tcp,FromPort=9300,ToPort=9300,IpRanges="[{CidrIp=${VPC_IP},Description='node communication within the VPC'}]"

  aws ec2 create-tags --resources ${SECURITY_GROUP_ID} --tags Key=Name,Value=${SG_NAME}

  echo "Group created"
fi

echo "Using security group: ${SECURITY_GROUP_ID}";
echo "********** FINISHED CREATING SECURITY GROUP ***********"

echo "*************** CREATING IAM ROLE ***************"

INSTANCE_PROFILE=`echo $(aws iam list-instance-profiles --path-prefix /elasticsearch/)`

if [ `echo ${INSTANCE_PROFILE} | jq '.InstanceProfiles | length'` -eq 1 ]
then
  echo "Profile $ROLE_NAME exists...."
else
  echo "Profile does not exist. Creating...."

  PROFILE=`echo $(aws iam create-instance-profile --path /elasticsearch/ --instance-profile-name ${ROLE_NAME})`

  echo "Profile created"
fi

ROLES=`echo $(aws iam list-roles --path-prefix /elasticsearch)`

if [ `echo ${ROLES} | jq '.Roles | length'` -eq 1 ]
then
  echo "Role $ROLE_NAME exists...."
else
  echo "Role does not exist. Creating...."

  TMP=`echo $(aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://01-trust-policy.json --path /elasticsearch/)`

  ROLE_ID=`echo ${TMP} | jq '.Role.RoleId' | tr -d '"'`

  sed  "s/my-bucket/${BUCKET_NAME}/g" ./01-policy-template.json | tee ./policy.json

  POLICY1=`echo $(aws iam create-policy --policy-name "${ROLE_NAME}-policy" --policy-document file://policy.json --description "elasticsearch access to s3 and instance descriptions")`

  BUCKET_POLICY_ARN=`echo ${POLICY1} | jq '.Policy.Arn' | tr -d '"'`

  echo "Bucket policy: $BUCKET_POLICY_ARN"

  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $BUCKET_POLICY_ARN

  aws iam add-role-to-instance-profile --instance-profile-name $ROLE_NAME --role-name $ROLE_NAME

  echo "Role created"
fi

echo "********** FINISHED CREATING ROLE ***********"