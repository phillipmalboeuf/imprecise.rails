#!/bin/bash
# Script to download or create AWS EC2 key pairs and save them to ~/.ssh

set -e

# Configuration
AWS_REGION="${AWS_REGION:-ca-central-1}"
SSH_DIR="$HOME/.ssh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AWS Key Pair Manager${NC}"
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

# Ensure .ssh directory exists
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# List existing key pairs
echo -e "${YELLOW}Existing AWS Key Pairs:${NC}"
aws ec2 describe-key-pairs \
    --region $AWS_REGION \
    --query 'KeyPairs[*].[KeyName,KeyPairId]' \
    --output table

echo ""
echo "What would you like to do?"
echo "1. Download an existing key pair (if you have the private key)"
echo "2. Create a new key pair and download it"
echo "3. List key pairs and check which ones exist locally"
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo ""
        read -p "Enter the key pair name to download: " KEY_NAME
        
        # Check if key pair exists in AWS
        KEY_EXISTS=$(aws ec2 describe-key-pairs \
            --key-names "$KEY_NAME" \
            --region $AWS_REGION \
            --query 'KeyPairs[0].KeyName' \
            --output text 2>/dev/null || echo "none")
        
        if [ "$KEY_EXISTS" == "none" ] || [ -z "$KEY_EXISTS" ]; then
            echo -e "${RED}ERROR: Key pair '$KEY_NAME' not found in AWS${NC}"
            exit 1
        fi
        
        # Check if private key already exists locally
        PRIVATE_KEY="$SSH_DIR/$KEY_NAME"
        if [ -f "$PRIVATE_KEY" ] || [ -f "$PRIVATE_KEY.pem" ]; then
            echo -e "${YELLOW}WARNING: Private key already exists locally${NC}"
            read -p "Overwrite? (y/N): " overwrite
            if [[ ! $overwrite =~ ^[Yy]$ ]]; then
                echo "Skipping..."
                exit 0
            fi
        fi
        
        echo -e "${YELLOW}NOTE: AWS does not store private keys.${NC}"
        echo "If you created this key pair in AWS, you should have downloaded"
        echo "the private key when you created it."
        echo ""
        echo "If you don't have the private key, you'll need to:"
        echo "  1. Create a new key pair (option 2)"
        echo "  2. Or import your existing public key"
        echo ""
        read -p "Do you have the private key file? (y/N): " has_key
        
        if [[ $has_key =~ ^[Yy]$ ]]; then
            read -p "Enter the path to your private key file: " KEY_PATH
            if [ -f "$KEY_PATH" ]; then
                cp "$KEY_PATH" "$PRIVATE_KEY"
                chmod 600 "$PRIVATE_KEY"
                echo -e "${GREEN}Copied private key to: $PRIVATE_KEY${NC}"
            else
                echo -e "${RED}ERROR: File not found: $KEY_PATH${NC}"
                exit 1
            fi
        else
            echo "Cannot download private key - AWS doesn't store it."
            echo "Please create a new key pair (option 2) or use your existing private key."
            exit 1
        fi
        ;;
        
    2)
        echo ""
        read -p "Enter a name for the new key pair: " KEY_NAME
        
        # Check if key pair already exists
        KEY_EXISTS=$(aws ec2 describe-key-pairs \
            --key-names "$KEY_NAME" \
            --region $AWS_REGION \
            --query 'KeyPairs[0].KeyName' \
            --output text 2>/dev/null || echo "none")
        
        if [ "$KEY_EXISTS" != "none" ] && [ -n "$KEY_EXISTS" ]; then
            echo -e "${RED}ERROR: Key pair '$KEY_NAME' already exists in AWS${NC}"
            echo "Please choose a different name or delete the existing one first."
            exit 1
        fi
        
        # Check if file already exists locally
        PRIVATE_KEY="$SSH_DIR/$KEY_NAME"
        if [ -f "$PRIVATE_KEY" ] || [ -f "$PRIVATE_KEY.pem" ]; then
            echo -e "${YELLOW}WARNING: File already exists: $PRIVATE_KEY${NC}"
            read -p "Overwrite? (y/N): " overwrite
            if [[ ! $overwrite =~ ^[Yy]$ ]]; then
                echo "Skipping..."
                exit 0
            fi
        fi
        
        echo "Creating new key pair: $KEY_NAME"
        echo "This will create the key pair in AWS and download the private key."
        echo ""
        
        # Create key pair and save private key
        aws ec2 create-key-pair \
            --key-name "$KEY_NAME" \
            --region $AWS_REGION \
            --query 'KeyMaterial' \
            --output text > "$PRIVATE_KEY"
        
        chmod 600 "$PRIVATE_KEY"
        
        echo -e "${GREEN}Key pair created successfully!${NC}"
        echo "Private key saved to: $PRIVATE_KEY"
        echo ""
        echo "You can now use this key pair:"
        echo "  export AWS_KEY_PAIR_NAME=$KEY_NAME"
        ;;
        
    3)
        echo ""
        echo -e "${YELLOW}Checking local key files...${NC}"
        echo ""
        
        # List AWS key pairs
        echo "AWS Key Pairs:"
        aws ec2 describe-key-pairs \
            --region $AWS_REGION \
            --query 'KeyPairs[*].KeyName' \
            --output text | tr '\t' '\n' | while read key_name; do
            if [ -n "$key_name" ]; then
                LOCAL_KEY="$SSH_DIR/$key_name"
                if [ -f "$LOCAL_KEY" ] || [ -f "$LOCAL_KEY.pem" ]; then
                    echo -e "  ${GREEN}✓${NC} $key_name (exists locally)"
                else
                    echo -e "  ${RED}✗${NC} $key_name (not found locally)"
                fi
            fi
        done
        
        echo ""
        echo "Local key files in ~/.ssh:"
        ls -1 "$SSH_DIR"/*.pem "$SSH_DIR"/*.key 2>/dev/null | while read key_file; do
            KEY_BASENAME=$(basename "$key_file" .pem)
            KEY_BASENAME=$(basename "$KEY_BASENAME" .key)
            KEY_EXISTS=$(aws ec2 describe-key-pairs \
                --key-names "$KEY_BASENAME" \
                --region $AWS_REGION \
                --query 'KeyPairs[0].KeyName' \
                --output text 2>/dev/null || echo "none")
            
            if [ "$KEY_EXISTS" != "none" ] && [ -n "$KEY_EXISTS" ]; then
                echo -e "  ${GREEN}✓${NC} $key_file (matches AWS key pair: $KEY_EXISTS)"
            else
                echo -e "  ${YELLOW}?${NC} $key_file (not found in AWS)"
            fi
        done || echo "  (no .pem or .key files found)"
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
