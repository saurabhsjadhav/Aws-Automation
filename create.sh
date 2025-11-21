#!/bin/bash

source config.env

echo "Validating AWS CLI..."
if ! command -v aws &>/dev/null; then
    echo "AWS CLI not installed."
    exit 1
fi
echo "AWS CLI found"

echo "Validating AWS credentials..."
aws sts get-caller-identity --region $AWS_REGION >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Invalid AWS credentials"
    exit 1
fi
echo "Credentials valid"

echo " Checking key pair..."
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region $AWS_REGION >/dev/null 2>&1; then
    echo " Key pair already exists. Skipping key creation."
else
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
        --region $AWS_REGION \
        --query "KeyMaterial" --output text > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
    echo "Key pair created"
fi

echo "Creating security group..."
SG_ID=$(aws ec2 describe-security-groups \
        --group-names "$SECURITY_GROUP_NAME" \
        --region $AWS_REGION \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "$SECURITY_GROUP_DESC" \
        --region $AWS_REGION \
        --query "GroupId" \
        --output text)
    
    echo "Adding inbound rule..."
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --region $AWS_REGION
    echo "SG created: $SG_ID"
else
    echo "Security group already exists: $SG_ID"
fi
echo " Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --region $AWS_REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)

echo "Waiting 20 seconds for instance to start..."
sleep 20

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region $AWS_REGION \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo " Instance launched: $INSTANCE_ID"
echo " Creating S3 bucket..."
RANDOM_VALUE=$RANDOM
BUCKET_NAME="${BUCKET_NAME_PREFIX}-${RANDOM_VALUE}"

aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION

echo "Bucket created: $BUCKET_NAME"

echo ""
echo "=============================================="
echo "RESOURCE CREATION SUMMARY"
echo " EC2 Instance ID : $INSTANCE_ID"
echo " Public IP       : $PUBLIC_IP"
echo " Security Group  : $SG_ID"
echo " Key Pair        : $KEY_NAME"
echo " S3 Bucket       : $BUCKET_NAME"
echo "=============================================="

