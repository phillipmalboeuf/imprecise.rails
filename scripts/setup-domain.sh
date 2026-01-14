#!/bin/bash
# Setup Route 53 and ACM for impreciseanalysis.com domain

set -e

DOMAIN="impreciseanalysis.com"
AWS_REGION="${AWS_REGION:-ca-central-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up domain infrastructure for $DOMAIN..."
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# 1. Create Route 53 hosted zone
echo "Creating Route 53 hosted zone..."
if aws route53 get-hosted-zone --id "/hostedzone/$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN}.'].[Id]" --output text | cut -d'/' -f3)" &>/dev/null 2>&1; then
  HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN}.'].[Id]" --output text | cut -d'/' -f3)
  echo "Hosted zone already exists: $HOSTED_ZONE_ID"
else
  HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
    --name "$DOMAIN" \
    --caller-reference "imprecise-$(date +%s)" \
    --query 'HostedZone.Id' \
    --output text | cut -d'/' -f3)
  echo "Created hosted zone: $HOSTED_ZONE_ID"
  
  # Get name servers
  NAME_SERVERS=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" --query 'DelegationSet.NameServers' --output text)
  echo ""
  echo "IMPORTANT: Update your domain registrar with these name servers:"
  for ns in $NAME_SERVERS; do
    echo "  - $ns"
  done
  echo ""
fi

# 2. Request ACM certificate for domain and wildcard
echo "Requesting ACM certificate..."
CERT_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='${DOMAIN}' || DomainName=='*.${DOMAIN}'].[CertificateArn]" \
  --output text \
  --region us-east-1 | head -n1)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
  echo "Creating new certificate request..."
  CERT_ARN=$(aws acm request-certificate \
    --domain-name "$DOMAIN" \
    --subject-alternative-names "*.${DOMAIN}" \
    --validation-method DNS \
    --region us-east-1 \
    --query 'CertificateArn' \
    --output text)
  
  echo "Certificate requested: $CERT_ARN"
  echo "Waiting for DNS validation records..."
  sleep 5
  
  # Get validation records
  CERT_VALIDATION=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region us-east-1 \
    --query 'Certificate.DomainValidationOptions' \
    --output json)
  
  echo ""
  echo "Add these DNS validation records to your Route 53 hosted zone:"
  echo "$CERT_VALIDATION" | jq -r '.[] | "Name: \(.ResourceRecord.Name)\nType: \(.ResourceRecord.Type)\nValue: \(.ResourceRecord.Value)"'
  echo ""
  echo "Or run this script again after adding the records to automatically create them."
else
  echo "Certificate already exists: $CERT_ARN"
  
  # Check if certificate is validated
  CERT_STATUS=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region us-east-1 \
    --query 'Certificate.Status' \
    --output text)
  
  if [ "$CERT_STATUS" != "ISSUED" ]; then
    echo "Certificate status: $CERT_STATUS"
    echo "Certificate needs validation. Getting DNS records..."
    
    CERT_VALIDATION=$(aws acm describe-certificate \
      --certificate-arn "$CERT_ARN" \
      --region us-east-1 \
      --query 'Certificate.DomainValidationOptions' \
      --output json)
    
    echo ""
    echo "Add these DNS validation records:"
    echo "$CERT_VALIDATION" | jq -r '.[] | "Name: \(.ResourceRecord.Name)\nType: \(.ResourceRecord.Type)\nValue: \(.ResourceRecord.Value)"'
  fi
fi

# 3. Create validation records in Route 53 (if certificate needs validation)
if [ -n "$CERT_ARN" ] && [ "$CERT_ARN" != "None" ]; then
  CERT_STATUS=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region us-east-1 \
    --query 'Certificate.Status' \
    --output text)
  
  if [ "$CERT_STATUS" != "ISSUED" ]; then
    echo ""
    echo "Creating DNS validation records in Route 53..."
    
    VALIDATION_RECORDS=$(aws acm describe-certificate \
      --certificate-arn "$CERT_ARN" \
      --region us-east-1 \
      --query 'Certificate.DomainValidationOptions' \
      --output json)
    
    echo "$VALIDATION_RECORDS" | jq -r '.[] | {
      "Name": .ResourceRecord.Name,
      "Type": .ResourceRecord.Type,
      "TTL": 300,
      "ResourceRecords": [{"Value": .ResourceRecord.Value}]
    }' | while read -r record; do
      RECORD_NAME=$(echo "$record" | jq -r '.Name')
      RECORD_TYPE=$(echo "$record" | jq -r '.Type')
      RECORD_VALUE=$(echo "$record" | jq -r '.ResourceRecords[0].Value')
      
      # Check if record already exists
      if ! aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${RECORD_NAME}' && Type=='${RECORD_TYPE}']" \
        --output text | grep -q .; then
        
        CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$RECORD_NAME",
      "Type": "$RECORD_TYPE",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$RECORD_VALUE"}]
    }
  }]
}
EOF
)
        
        aws route53 change-resource-record-sets \
          --hosted-zone-id "$HOSTED_ZONE_ID" \
          --change-batch "$CHANGE_BATCH"
        
        echo "Created validation record: $RECORD_NAME"
      else
        echo "Validation record already exists: $RECORD_NAME"
      fi
    done
  fi
fi

# 4. Create IAM policy for Route 53 access
echo ""
echo "Creating IAM policy for Route 53 access..."
POLICY_NAME="imprecise-route53-access"

if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" &>/dev/null; then
  echo "Policy $POLICY_NAME already exists"
else
  cat > /tmp/route53-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListHostedZones"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/route53-policy.json \
    --description "Allow Route 53 DNS record management for imprecise deployments"
  
  echo "Policy $POLICY_NAME created"
fi

# Attach policy to GitHub deploy role
GITHUB_ROLE_NAME="imprecise-github-deploy-role"
if aws iam get-role --role-name "$GITHUB_ROLE_NAME" &>/dev/null; then
  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
  aws iam attach-role-policy \
    --role-name "$GITHUB_ROLE_NAME" \
    --policy-arn "$POLICY_ARN"
  echo "Attached Route 53 policy to $GITHUB_ROLE_NAME"
fi

echo ""
echo "Domain setup complete!"
echo ""
echo "Summary:"
echo "  - Hosted Zone ID: $HOSTED_ZONE_ID"
echo "  - Certificate ARN: $CERT_ARN"
echo "  - Domain: $DOMAIN"
echo ""
echo "Next steps:"
echo "1. Update your domain registrar with the name servers shown above"
echo "2. Wait for certificate validation (can take up to 30 minutes)"
echo "3. Push to a branch to trigger deployment with domain setup"
echo ""
echo "To check certificate status:"
echo "  aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query 'Certificate.Status'"
