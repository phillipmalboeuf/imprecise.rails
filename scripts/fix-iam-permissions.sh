#!/bin/bash
# Quick fix script to add missing IAM permissions for GitHub Actions deployment

set -e

AWS_REGION="${AWS_REGION:-ca-central-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GITHUB_ROLE_NAME="imprecise-github-deploy-role"

echo "Fixing IAM permissions for GitHub Actions deployment..."
echo "Account ID: $ACCOUNT_ID"
echo ""

# Update the deploy policy to include iam:PassRole
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
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/imprecise-deploy-instance-role"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:GetInstanceProfile"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:instance-profile/imprecise-deploy-instance-profile"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:imprecise-*",
        "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:rds!*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "acm:ListCertificates",
        "acm:DescribeCertificate"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:StartSession",
        "ssm:DescribeInstanceInformation"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::imprecise-deployments",
        "arn:aws:s3:::imprecise-deployments/*"
      ]
    }
  ]
}
EOF

# Update the policy
aws iam put-role-policy \
  --role-name "$GITHUB_ROLE_NAME" \
  --policy-name DeployPolicy \
  --policy-document file:///tmp/deploy-policy.json

echo "✅ Updated DeployPolicy for $GITHUB_ROLE_NAME"
echo ""
echo "The policy now includes:"
echo "  - iam:PassRole (to attach IAM role to EC2 instances)"
echo "  - iam:GetInstanceProfile (to get instance profile details)"
echo ""
echo "You can now retry your GitHub Actions deployment."
