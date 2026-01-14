#!/bin/bash
# Store RAILS_MASTER_KEY in AWS Secrets Manager

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"
SECRET_NAME="imprecise-rails-master-key"

echo "Storing RAILS_MASTER_KEY in AWS Secrets Manager..."
echo ""

# Check if master.key file exists
if [ -f "config/master.key" ]; then
  echo "Reading master.key from config/master.key..."
  MASTER_KEY=$(cat config/master.key)
elif [ -n "$RAILS_MASTER_KEY" ]; then
  echo "Using RAILS_MASTER_KEY from environment..."
  MASTER_KEY="$RAILS_MASTER_KEY"
else
  echo "Please provide your RAILS_MASTER_KEY:"
  read -s MASTER_KEY
  echo ""
fi

if [ -z "$MASTER_KEY" ]; then
  echo "Error: Master key is empty"
  exit 1
fi

# Check if secret exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "Updating existing secret: $SECRET_NAME"
  aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "$MASTER_KEY" \
    --region "$AWS_REGION"
  echo "Secret updated successfully!"
else
  echo "Creating new secret: $SECRET_NAME"
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Rails master key for imprecise application" \
    --secret-string "$MASTER_KEY" \
    --region "$AWS_REGION"
  echo "Secret created successfully!"
fi

echo ""
echo "Secret ARN:"
aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text
