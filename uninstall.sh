#!/bin/bash

# Load configuration
source config.env
echo "🚨 Starting Cleanup..."

# ---------------------------
# TERMINATE INSTANCES
# ---------------------------
echo "🛑 Checking EC2 instances with Name=$INSTANCE_NAME..."

INSTANCE_IDS=$(aws ec2 describe-instances \
 --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
 --region $AWS_REGION \
 --query "Reservations[].Instances[].InstanceId" \
 --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "✔ No EC2 instances found."
else
    echo "🔻 Terminating instances: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region $AWS_REGION >/dev/null
    
    echo "⏳ Waiting for termination to complete..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region $AWS_REGION
    echo "✔ EC2 instances terminated"
fi


# ---------------------------
# DELETE SECURITY GROUP
# ---------------------------
echo "🛡 Checking Security Group..."

SG_ID=$(aws ec2 describe-security-groups \
 --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
 --region $AWS_REGION \
 --query "SecurityGroups[0].GroupId" \
 --output text 2>/dev/null)

if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
    echo "🔻 Deleting Security Group: $SG_ID"
    aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION
    echo "✔ Security group deleted"
else
    echo "✔ No security group found"
fi


# ---------------------------
# DELETE KEY PAIR + LOCAL FILE
# ---------------------------
echo "🔐 Checking key pair..."

if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region $AWS_REGION >/dev/null 2>&1; then
    echo "🔻 Deleting key pair..."
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region $AWS_REGION
    
    if [ -f "$KEY_NAME.pem" ]; then
        rm -f "$KEY_NAME.pem"
        echo "✔ Local PEM file deleted"
    fi
    echo "✔ Key pair deleted"
else
    echo "✔ No key pair found"
fi


# ---------------------------
# DELETE S3 BUCKETS WITH PREFIX
# ---------------------------
echo "🪣 Searching S3 buckets with prefix: $BUCKET_NAME_PREFIX"

BUCKETS=$(aws s3api list-buckets \
 --query "Buckets[?starts_with(Name, '$BUCKET_NAME_PREFIX')].Name" \
 --output text)

if [ -z "$BUCKETS" ]; then
    echo "✔ No buckets found with prefix"
else
    for bucket in $BUCKETS; do
        echo "🔻 Removing bucket: $bucket"
        aws s3 rb s3://$bucket --force --region $AWS_REGION
    done
fi


# ---------------------------
# SUMMARY
# ---------------------------
echo ""
echo "=============================================="
echo "✔ CLEANUP SUMMARY"
echo " EC2 Instances      : Deleted"
echo " Security Group     : Deleted (if existed)"
echo " Key Pair           : Deleted + PEM removed"
echo " S3 Buckets         : Deleted"
echo "=============================================="s