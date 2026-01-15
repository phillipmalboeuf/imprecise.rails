#!/bin/bash
# Script to add SSH (port 22) access to an AWS security group

set -e

# Configuration
AWS_REGION="${AWS_REGION:-ca-central-1}"
SECURITY_GROUP_ID="${AWS_SECURITY_GROUP_ID}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Adding SSH Access to Security Group${NC}"
echo "Region: $AWS_REGION"
echo ""

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}"
    exit 1
fi

# Get security group ID if not provided
if [ -z "$SECURITY_GROUP_ID" ]; then
    echo -e "${YELLOW}No security group ID provided. Listing your security groups...${NC}"
    echo ""
    aws ec2 describe-security-groups \
        --region $AWS_REGION \
        --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
        --output table
    
    echo ""
    read -p "Enter the Security Group ID (sg-xxxxx): " SECURITY_GROUP_ID
    
    if [ -z "$SECURITY_GROUP_ID" ]; then
        echo -e "${RED}ERROR: Security group ID is required${NC}"
        exit 1
    fi
fi

# Verify security group exists
SG_EXISTS=$(aws ec2 describe-security-groups \
    --group-ids "$SECURITY_GROUP_ID" \
    --region $AWS_REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "none")

if [ "$SG_EXISTS" == "none" ] || [ -z "$SG_EXISTS" ]; then
    echo -e "${RED}ERROR: Security group $SECURITY_GROUP_ID not found!${NC}"
    exit 1
fi

echo -e "${GREEN}Security group found: $SECURITY_GROUP_ID${NC}"
echo ""

# Check if SSH rule already exists
SSH_RULE=$(aws ec2 describe-security-groups \
    --group-ids "$SECURITY_GROUP_ID" \
    --region $AWS_REGION \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` || ToPort==`22`]' \
    --output text 2>/dev/null || echo "")

if [ -n "$SSH_RULE" ]; then
    echo -e "${YELLOW}SSH (port 22) access already exists in this security group${NC}"
    echo ""
    echo "Current SSH rules:"
    aws ec2 describe-security-groups \
        --group-ids "$SECURITY_GROUP_ID" \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` || ToPort==`22`].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
        --output table
    echo ""
    read -p "Add another SSH rule anyway? (y/N): " add_anyway
    if [[ ! $add_anyway =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi

# Ask for IP range
echo "Choose IP range for SSH access:"
echo "1. Allow from anywhere (0.0.0.0/0) - Less secure but works for CI/CD"
echo "2. Allow from your current IP only - More secure"
echo "3. Allow from GitHub Actions IP ranges - Most secure for CI/CD"
echo "4. Custom CIDR"
read -p "Enter choice (1-4): " choice

case $choice in
    1)
        CIDR="0.0.0.0/0"
        echo -e "${YELLOW}Warning: This allows SSH from anywhere on the internet${NC}"
        ;;
    2)
        CURRENT_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")
        if [ -z "$CURRENT_IP" ]; then
            echo -e "${RED}ERROR: Could not determine your current IP${NC}"
            read -p "Enter your IP address (e.g., 1.2.3.4): " CURRENT_IP
        fi
        CIDR="$CURRENT_IP/32"
        echo "Using your current IP: $CURRENT_IP"
        ;;
    3)
        # GitHub Actions IP ranges (these change, so this is approximate)
        echo "Adding GitHub Actions IP ranges..."
        CIDR="0.0.0.0/0"  # GitHub IPs change frequently, so we'll use 0.0.0.0/0 with a note
        echo -e "${YELLOW}Note: GitHub Actions IPs change frequently. Using 0.0.0.0/0 for CI/CD.${NC}"
        echo "For production, consider using AWS VPC endpoints or restricting further."
        ;;
    4)
        read -p "Enter CIDR block (e.g., 1.2.3.4/32 or 10.0.0.0/16): " CIDR
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
read -p "Add SSH access from $CIDR? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Add SSH rule
echo ""
echo "Adding SSH (port 22) access rule..."
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$CIDR" \
    --region $AWS_REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SSH access rule added successfully!${NC}"
    echo ""
    echo "Updated SSH rules:"
    aws ec2 describe-security-groups \
        --group-ids "$SECURITY_GROUP_ID" \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` || ToPort==`22`].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
        --output table
else
    echo -e "${RED}ERROR: Failed to add SSH access rule${NC}"
    echo "The rule might already exist, or there was an AWS API error."
    exit 1
fi

echo ""
echo -e "${GREEN}Done!${NC}"
