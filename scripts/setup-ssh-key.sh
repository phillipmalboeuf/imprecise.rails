#!/bin/bash
# Generate SSH key pair for EC2 instance access and store in AWS Secrets Manager

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"
KEY_NAME="imprecise-deploy-key"
SECRET_NAME="imprecise-ec2-ssh-private-key"

echo "Setting up SSH key pair for EC2 instance access..."
echo ""

# Check if key already exists in Secrets Manager
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "SSH key already exists in Secrets Manager: $SECRET_NAME"
  echo ""
  echo "To view the public key, run:"
  echo "  aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $AWS_REGION --query 'SecretString' --output text | jq -r '.public_key'"
  echo ""
  echo "To regenerate, delete the secret first:"
  echo "  aws secretsmanager delete-secret --secret-id $SECRET_NAME --region $AWS_REGION"
  exit 0
fi

# Generate SSH key pair
echo "Generating SSH key pair..."
ssh-keygen -t ed25519 -f /tmp/$KEY_NAME -N "" -C "imprecise-deploy-key"

# Read the keys
PRIVATE_KEY=$(cat /tmp/$KEY_NAME)
PUBLIC_KEY=$(cat /tmp/$KEY_NAME.pub)

# Store in Secrets Manager as JSON using jq to properly escape the private key
SECRET_VALUE=$(jq -n \
  --arg private_key "$PRIVATE_KEY" \
  --arg public_key "$PUBLIC_KEY" \
  '{private_key: $private_key, public_key: $public_key}')

# Create secret
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "SSH private and public key for EC2 instance access" \
  --secret-string "$SECRET_VALUE" \
  --region "$AWS_REGION"

echo "✅ SSH key pair created and stored in Secrets Manager"
echo ""
echo "Secret name: $SECRET_NAME"
echo ""
echo "Public key:"
echo "$PUBLIC_KEY"
echo ""
echo "Add this to your GitHub repository secrets:"
echo "  Name: EC2_SSH_PRIVATE_KEY"
echo "  Value: (the private key from Secrets Manager)"
echo ""
echo "To get the private key:"
echo "  aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $AWS_REGION --query 'SecretString' --output text | jq -r '.private_key'"
echo ""
echo "⚠️  Clean up local key files:"
rm -f /tmp/$KEY_NAME /tmp/$KEY_NAME.pub
