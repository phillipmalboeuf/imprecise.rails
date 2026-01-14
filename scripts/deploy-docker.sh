#!/bin/bash
# Simple Docker deployment script (no Kamal needed)

set -e

BRANCH_NAME="${1:-main}"
SANITIZED_BRANCH=$(echo "$BRANCH_NAME" | sed 's/\//-/g' | tr '[:upper:]' '[:lower:]')
INSTANCE_ID="${2}"
AWS_REGION="${AWS_REGION:-ca-central-1}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Usage: $0 <branch-name> <instance-id>"
  exit 1
fi

echo "Deploying branch '$BRANCH_NAME' to instance $INSTANCE_ID"
echo "Sanitized branch: $SANITIZED_BRANCH"
echo ""

# Get secrets from AWS Secrets Manager
echo "Fetching secrets..."
RAILS_MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id imprecise-rails-master-key \
  --query 'SecretString' \
  --output text \
  --region "$AWS_REGION")

RDS_INFO=$(aws rds describe-db-instances \
  --db-instance-identifier postgres-standard \
  --query 'DBInstances[0].[Endpoint.Address,MasterUserSecret.SecretArn]' \
  --output text \
  --region "$AWS_REGION")

RDS_ENDPOINT=$(echo "$RDS_INFO" | awk '{print $1}')
RDS_SECRET_ARN=$(echo "$RDS_INFO" | awk '{print $2}')

if [ -n "$RDS_SECRET_ARN" ] && [ "$RDS_SECRET_ARN" != "None" ]; then
  RDS_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$RDS_SECRET_ARN" \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" | jq -r '.password // .')
else
  RDS_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id imprecise-rds-password \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")
fi

# Prepare deployment script
DEPLOY_SCRIPT=$(cat <<DEPLOY_EOF
#!/bin/bash
set -e

BRANCH="$SANITIZED_BRANCH"
IMAGE_NAME="imprecise-\$BRANCH"
CONTAINER_NAME="imprecise-\$BRANCH-web"
RAILS_MASTER_KEY="$RAILS_MASTER_KEY"
DB_HOST="$RDS_ENDPOINT"
DB_USERNAME="postgres"
DB_PASSWORD="$RDS_PASSWORD"
DB_DATABASE="imprecise_\${BRANCH}_production"
DB_PORT="5432"

echo "Stopping existing container..."
docker stop \$CONTAINER_NAME 2>/dev/null || true
docker rm \$CONTAINER_NAME 2>/dev/null || true

echo "Building Docker image..."
cd /home/ubuntu/app
docker build -t \$IMAGE_NAME .

echo "Starting container..."
docker run -d \\
  --name \$CONTAINER_NAME \\
  --restart unless-stopped \\
  -p 3000:80 \\
  -e RAILS_ENV=production \\
  -e RAILS_MASTER_KEY="\$RAILS_MASTER_KEY" \\
  -e DB_HOST="\$DB_HOST" \\
  -e DB_USERNAME="\$DB_USERNAME" \\
  -e DB_PASSWORD="\$DB_PASSWORD" \\
  -e DB_DATABASE="\$DB_DATABASE" \\
  -e DB_PORT="\$DB_PORT" \\
  -v imprecise_\${BRANCH}_storage:/rails/storage \\
  \$IMAGE_NAME

echo "Container started. Checking status..."
sleep 5
docker ps | grep \$CONTAINER_NAME || echo "Warning: Container not running"
docker logs --tail 50 \$CONTAINER_NAME || true
DEPLOY_EOF
)

# Send deployment script to instance via SSM
echo "Deploying via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[$(echo "$DEPLOY_SCRIPT" | jq -Rs .)]" \
  --region "$AWS_REGION" \
  --output text --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting for deployment to complete..."
sleep 10

# Monitor command output
for i in {1..30}; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "InProgress")
  
  if [ "$STATUS" == "Success" ] || [ "$STATUS" == "Failed" ]; then
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done

# Get output
OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "")

ERROR_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "")

echo ""
echo "=== Deployment Output ==="
echo "$OUTPUT"

if [ -n "$ERROR_OUTPUT" ]; then
  echo ""
  echo "=== Errors ==="
  echo "$ERROR_OUTPUT"
fi

STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'Status' \
  --output text 2>/dev/null || echo "Unknown")

if [ "$STATUS" == "Success" ]; then
  echo ""
  echo "✅ Deployment successful!"
else
  echo ""
  echo "❌ Deployment failed with status: $STATUS"
  exit 1
fi
