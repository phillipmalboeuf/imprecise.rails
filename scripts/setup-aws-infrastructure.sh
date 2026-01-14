#!/bin/bash
# Setup AWS infrastructure for branch-based deployments

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up AWS infrastructure for branch-based deployments..."
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"

# 1. Create IAM role for EC2 instances
echo "Creating IAM role for EC2 instances..."
ROLE_NAME="imprecise-deploy-instance-role"

# Check if role exists
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "IAM role $ROLE_NAME already exists"
else
  # Create trust policy
  cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  # Create role
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "IAM role for imprecise Rails deployment EC2 instances"

  # Attach policies
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

  # Create custom policy for Secrets Manager access
  cat > /tmp/secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:imprecise-*"
    }
  ]
}
EOF

  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name SecretsManagerAccess \
    --policy-document file:///tmp/secrets-policy.json

  echo "IAM role $ROLE_NAME created"
fi

# 2. Create instance profile
echo "Creating instance profile..."
PROFILE_NAME="imprecise-deploy-instance-profile"

if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" &>/dev/null; then
  echo "Instance profile $PROFILE_NAME already exists"
else
  aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME"
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$PROFILE_NAME" \
    --role-name "$ROLE_NAME"
  echo "Instance profile $PROFILE_NAME created"
fi

# 3. Create IAM role for GitHub Actions (OIDC)
echo "Creating IAM role for GitHub Actions..."
GITHUB_ROLE_NAME="imprecise-github-deploy-role"

# Get GitHub repository (you'll need to set this)
GITHUB_REPO="${GITHUB_REPO:-phillipmalboeuf/imprecise.rails}"
GITHUB_ORG=$(echo "$GITHUB_REPO" | cut -d'/' -f1)

if aws iam get-role --role-name "$GITHUB_ROLE_NAME" &>/dev/null; then
  echo "IAM role $GITHUB_ROLE_NAME already exists"
else
  # Create OIDC provider if it doesn't exist
  if ! aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')]" --output text | grep -q .; then
    echo "Creating OIDC provider for GitHub..."
    aws iam create-open-id-connect-provider \
      --url https://token.actions.githubusercontent.com \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
  fi

  # Create trust policy for GitHub Actions
  cat > /tmp/github-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF

  aws iam create-role \
    --role-name "$GITHUB_ROLE_NAME" \
    --assume-role-policy-document file:///tmp/github-trust-policy.json \
    --description "IAM role for GitHub Actions to deploy imprecise Rails app"

  # Attach policies for deployment
  aws iam attach-role-policy \
    --role-name "$GITHUB_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

  aws iam attach-role-policy \
    --role-name "$GITHUB_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess

  # Create custom policy for deployment operations
  cat > /tmp/deploy-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:RunInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DeleteSecurityGroup",
        "ec2:AssociateIamInstanceProfile",
        "ec2:ReplaceIamInstanceProfileAssociation"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:imprecise-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  aws iam put-role-policy \
    --role-name "$GITHUB_ROLE_NAME" \
    --policy-name DeployPolicy \
    --policy-document file:///tmp/deploy-policy.json

  echo "IAM role $GITHUB_ROLE_NAME created"
  echo ""
  echo "Add this to your GitHub repository secrets:"
  echo "AWS_DEPLOY_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${GITHUB_ROLE_NAME}"
fi

# 4. Store RAILS_MASTER_KEY in Secrets Manager
echo "Setting up RAILS_MASTER_KEY in Secrets Manager..."
SECRET_NAME="imprecise-rails-master-key"

if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "Secret $SECRET_NAME already exists"
  echo "To update it, run:"
  echo "aws secretsmanager update-secret --secret-id $SECRET_NAME --secret-string 'YOUR_MASTER_KEY' --region $AWS_REGION"
else
  echo "Creating secret $SECRET_NAME..."
  echo "Please provide your RAILS_MASTER_KEY:"
  read -s MASTER_KEY
  echo ""
  
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Rails master key for imprecise application" \
    --secret-string "$MASTER_KEY" \
    --region "$AWS_REGION"
  
  echo "Secret $SECRET_NAME created"
fi

# 5. Create RDS database for each branch (optional - can be done on-demand)
echo ""
echo "Infrastructure setup complete!"
echo ""
echo "Next steps:"
echo "1. Add AWS_DEPLOY_ROLE_ARN to GitHub repository secrets"
echo "2. Ensure RAILS_MASTER_KEY is stored in Secrets Manager"
echo "3. Push to any branch to trigger deployment"
echo ""
echo "GitHub Actions will automatically:"
echo "- Create EC2 instances for each branch"
echo "- Deploy the latest commit from each branch"
echo "- Configure each instance with the master.key"
