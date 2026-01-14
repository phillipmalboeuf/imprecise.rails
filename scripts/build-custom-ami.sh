#!/bin/bash
# Build a custom AMI with Docker and Kamal pre-installed

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"
AMI_NAME="imprecise-ubuntu-docker-kamal"
INSTANCE_TYPE="t3.micro"

echo "Building custom AMI: $AMI_NAME"
echo "Region: $AWS_REGION"
echo ""

# Get latest Ubuntu 22.04 LTS AMI
echo "Finding latest Ubuntu 22.04 LTS AMI..."
BASE_AMI=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --region "$AWS_REGION")

echo "Base AMI: $BASE_AMI"
echo ""

# Get default VPC and subnet
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region "$AWS_REGION")

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --region "$AWS_REGION")

# Create temporary security group
echo "Creating temporary security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "imprecise-ami-build-$(date +%s)" \
  --description "Temporary security group for AMI build" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' \
  --output text)

# Allow SSH from anywhere (temporary, for build)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" > /dev/null

echo "Security group created: $SG_ID"
echo ""

# Prepare user data script
USER_DATA=$(cat <<'USERDATA_EOF'
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting AMI build process at $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install base packages
apt-get install -y \
  curl \
  wget \
  git \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release \
  snapd \
  jq

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install Kamal
curl -fsSL https://github.com/basecamp/kamal/releases/latest/download/kamal-linux-amd64 -o /usr/local/bin/kamal
chmod +x /usr/local/bin/kamal

# Install PostgreSQL client
apt-get install -y postgresql-client

# Install SSM agent
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Create app directory
mkdir -p /home/ubuntu/app
chown ubuntu:ubuntu /home/ubuntu/app

# Clean up
apt-get autoremove -y
apt-get autoclean

echo "AMI build completed at $(date)"
echo "Docker version: $(docker --version)"
echo "Kamal version: $(kamal version)"
USERDATA_EOF
)

# Launch instance for AMI build
echo "Launching instance for AMI build..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$BASE_AMI" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --iam-instance-profile Name=imprecise-deploy-instance-profile \
  --user-data "$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=imprecise-ami-build},{Key=Purpose,Value=AMI-creation}]" \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance launched: $INSTANCE_ID"
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

echo "Instance launched: $INSTANCE_ID"
echo "Waiting for SSM agent to be ready..."
sleep 30

# Wait for SSM to be ready
for i in {1..20}; do
  if aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null | grep -q "Online"; then
    echo "SSM agent is ready!"
    break
  fi
  echo "Waiting for SSM agent... ($i/20)"
  sleep 10
done

echo ""
echo "Waiting for user-data script to complete (this may take 5-10 minutes)..."
echo ""

# Wait for user-data to complete (check via SSM)
for i in {1..60}; do
  CHECK_CMD_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["grep -q \"AMI build completed\" /var/log/user-data.log && echo \"COMPLETE\" || echo \"IN_PROGRESS\""]' \
    --region "$AWS_REGION" \
    --output text --query 'Command.CommandId' 2>/dev/null || echo "")
  
  if [ -n "$CHECK_CMD_ID" ]; then
    sleep 5
    STATUS=$(aws ssm get-command-invocation \
      --command-id "$CHECK_CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query 'StandardOutputContent' \
      --output text 2>/dev/null || echo "")
    
    if echo "$STATUS" | grep -q "COMPLETE"; then
      echo "User-data script completed!"
      break
    fi
  fi
  
  echo "Waiting... ($i/60)"
  sleep 10
done

# Verify installations via SSM
echo ""
echo "Verifying installations..."
VERIFY_COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker --version", "kamal version", "echo \"All installations verified!\""]' \
  --region "$AWS_REGION" \
  --output text --query 'Command.CommandId')

sleep 5
aws ssm get-command-invocation \
  --command-id "$VERIFY_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardOutputContent' \
  --output text

# Stop instance before creating AMI
echo ""
echo "Stopping instance before creating AMI..."
aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

# Create AMI
echo ""
echo "Creating AMI from instance..."
AMI_ID=$(aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "Ubuntu 22.04 with Docker and Kamal pre-installed for imprecise deployments" \
  --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Purpose,Value=imprecise-deployment}]" \
  --region "$AWS_REGION" \
  --query 'ImageId' \
  --output text)

echo "AMI creation started: $AMI_ID"
echo "Waiting for AMI to be available (this may take 10-15 minutes)..."
aws ec2 wait image-available --image-ids "$AMI_ID" --region "$AWS_REGION"

echo ""
echo "✅ AMI created successfully!"
echo "AMI ID: $AMI_ID"
echo "AMI Name: $AMI_NAME"
echo ""
echo "Cleaning up build instance..."
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" > /dev/null

# Delete temporary security group
echo "Cleaning up temporary security group..."
aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" > /dev/null

echo ""
echo "✅ Custom AMI is ready!"
echo ""
echo "Update your workflow to use this AMI by setting:"
echo "  CUSTOM_AMI_ID=$AMI_ID"
echo ""
echo "Or store it in AWS Systems Manager Parameter Store:"
echo "  aws ssm put-parameter --name /imprecise/custom-ami-id --value $AMI_ID --type String --region $AWS_REGION"
