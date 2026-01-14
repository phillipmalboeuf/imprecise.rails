#!/bin/bash
# Add SSH public key to an existing EC2 instance via SSM

set -e

INSTANCE_ID="${1}"
AWS_REGION="${AWS_REGION:-ca-central-1}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Usage: $0 <instance-id>"
  echo ""
  echo "Example: $0 i-0123456789abcdef0"
  exit 1
fi

echo "Adding SSH public key to instance: $INSTANCE_ID"
echo ""

# Get SSH public key from Secrets Manager
SSH_KEY_JSON=$(aws secretsmanager get-secret-value \
  --secret-id imprecise-ec2-ssh-private-key \
  --query 'SecretString' \
  --output text \
  --region "$AWS_REGION" 2>/dev/null || echo '{}')

SSH_PUBLIC_KEY=$(echo "$SSH_KEY_JSON" | jq -r '.public_key // empty' 2>/dev/null || echo "")

if [ -z "$SSH_PUBLIC_KEY" ] || [ "$SSH_PUBLIC_KEY" == "null" ]; then
  echo "Error: SSH key not found in Secrets Manager."
  echo "Run ./scripts/setup-ssh-key.sh first."
  exit 1
fi

echo "Public key to add:"
echo "$SSH_PUBLIC_KEY"
echo ""

# Use SSM to add the key
SSM_PARAMS=$(jq -n \
  --arg key "$SSH_PUBLIC_KEY" \
  '{
    "commands": [
      "mkdir -p /home/ubuntu/.ssh",
      "chmod 700 /home/ubuntu/.ssh",
      ("echo \"" + $key + "\" > /home/ubuntu/.ssh/authorized_keys"),
      "chmod 600 /home/ubuntu/.ssh/authorized_keys",
      "chown -R ubuntu:ubuntu /home/ubuntu/.ssh"
    ]
  }')

echo "Sending SSM command to instance..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "$SSM_PARAMS" \
  --region "$AWS_REGION" \
  --output text --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo ""
echo "Waiting for command to complete..."
sleep 10

# Check command status
STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'Status' \
  --output text 2>/dev/null || echo "InProgress")

echo "Command status: $STATUS"

if [ "$STATUS" == "Success" ]; then
  echo "✅ SSH key added successfully!"
  echo ""
  echo "You can now SSH into the instance using:"
  echo "  ssh -i ~/.ssh/deploy_key ubuntu@<instance-ip>"
else
  echo "⚠️  Command may still be running. Check status with:"
  echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID --region $AWS_REGION"
fi
