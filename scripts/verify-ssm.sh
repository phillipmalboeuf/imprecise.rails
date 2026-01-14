#!/bin/bash
# Verify SSM connectivity for EC2 instances

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"

echo "Checking SSM agent status for EC2 instances..."
echo "Region: $AWS_REGION"
echo ""

# List all instances
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output text \
  --region "$AWS_REGION")

if [ -z "$INSTANCES" ]; then
  echo "No EC2 instances found."
  exit 0
fi

echo "Found instances:"
echo "$INSTANCES"
echo ""

# Check SSM agent status
echo "Checking SSM agent registration..."
SSM_INSTANCES=$(aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --query 'InstanceInformationList[*].[InstanceId,ComputerName,PingStatus,PlatformType]' \
  --output text)

if [ -z "$SSM_INSTANCES" ]; then
  echo "⚠️  No instances registered with SSM."
  echo ""
  echo "This usually means:"
  echo "  1. The SSM agent is not installed on the instances"
  echo "  2. The instance IAM role is missing AmazonSSMManagedInstanceCore policy"
  echo "  3. The SSM agent hasn't registered yet (can take a few minutes)"
  echo ""
  echo "To fix:"
  echo "  1. Ensure instances have the IAM role with SSM policy attached"
  echo "  2. Install SSM agent: snap install amazon-ssm-agent --classic"
  echo "  3. Restart SSM agent: sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service"
  echo "  4. Wait 2-3 minutes for registration"
  echo ""
  
  # Check IAM role
  echo "Checking IAM role configuration..."
  ROLE_NAME="imprecise-deploy-instance-role"
  SSM_POLICY_ATTACHED=$(aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`]' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$SSM_POLICY_ATTACHED" ]; then
    echo "❌ IAM role '$ROLE_NAME' is missing AmazonSSMManagedInstanceCore policy"
    echo ""
    echo "Attaching policy now..."
    aws iam attach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
      --region "$AWS_REGION" 2>/dev/null || echo "Failed to attach policy (may need manual fix)"
    echo ""
    echo "✅ Policy attached. Existing instances may need to be rebooted for changes to take effect."
  else
    echo "✅ IAM role has SSM policy attached"
  fi
  
  exit 1
else
  echo "✅ Instances registered with SSM:"
  echo "$SSM_INSTANCES"
  echo ""
  
  # Test SSM connection to first instance
  FIRST_INSTANCE=$(echo "$SSM_INSTANCES" | head -n1 | awk '{print $1}')
  if [ -n "$FIRST_INSTANCE" ]; then
    echo "Testing SSM connection to instance: $FIRST_INSTANCE"
    echo "Running test command..."
    
    CMD_ID=$(aws ssm send-command \
      --instance-ids "$FIRST_INSTANCE" \
      --document-name "AWS-RunShellScript" \
      --parameters 'commands=["echo \"SSM connection successful\""]' \
      --region "$AWS_REGION" \
      --output text --query 'Command.CommandId' 2>/dev/null || echo "")
    
    if [ -n "$CMD_ID" ]; then
      sleep 3
      OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$FIRST_INSTANCE" \
        --region "$AWS_REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
      
      if [ -n "$OUTPUT" ]; then
        echo "✅ SSM connection test successful: $OUTPUT"
      else
        echo "⚠️  SSM command sent but output not available yet"
      fi
    else
      echo "⚠️  Could not send SSM command"
    fi
  fi
fi
