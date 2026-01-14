# SSH Key Setup for EC2 Access

This guide explains how to set up SSH keys for GitHub Actions to access EC2 instances for deployment.

## Quick Setup

Run the setup script to generate and store SSH keys:

```bash
./scripts/setup-ssh-key.sh
```

This will:
1. Generate an ED25519 SSH key pair
2. Store both keys in AWS Secrets Manager (`imprecise-ec2-ssh-private-key`)
3. Display the public key for reference

## How It Works

1. **Key Generation**: The script creates an ED25519 SSH key pair (more secure than RSA)
2. **Storage**: Both private and public keys are stored in AWS Secrets Manager as JSON
3. **EC2 Configuration**: The public key is automatically added to EC2 instances via user-data script
4. **GitHub Actions**: The workflow retrieves the private key from Secrets Manager and uses it for SSH access

## Manual Setup (Alternative)

If you prefer to use your own SSH key:

1. **Generate a key pair** (if you don't have one):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/imprecise-deploy-key -N "" -C "imprecise-deploy"
   ```

2. **Store in Secrets Manager**:
   ```bash
   aws secretsmanager create-secret \
     --name imprecise-ec2-ssh-private-key \
     --secret-string "{\"private_key\":\"$(cat ~/.ssh/imprecise-deploy-key)\",\"public_key\":\"$(cat ~/.ssh/imprecise-deploy-key.pub)\"}" \
     --region ca-central-1
   ```

3. **Add public key to existing instances** (if any):
   ```bash
   # Get the public key
   PUBLIC_KEY=$(aws secretsmanager get-secret-value \
     --secret-id imprecise-ec2-ssh-private-key \
     --query 'SecretString' \
     --output text \
     --region ca-central-1 | jq -r '.public_key')
   
   # Add to instance (you'll need another way to access it first)
   ssh ubuntu@<instance-ip> "echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys"
   ```

## Verification

After setup, verify the key is stored:

```bash
aws secretsmanager get-secret-value \
  --secret-id imprecise-ec2-ssh-private-key \
  --region ca-central-1 \
  --query 'SecretString' \
  --output text | jq -r '.public_key'
```

## Security Notes

- **Private Key**: Never commit the private key to git (already in .gitignore)
- **Secrets Manager**: Keys are encrypted at rest using AWS KMS
- **IAM Access**: Only the GitHub Actions role can read the secret
- **Key Rotation**: To rotate keys, generate new ones and update the secret

## Troubleshooting

### "SSH key not found" error

1. Run the setup script: `./scripts/setup-ssh-key.sh`
2. Verify the secret exists:
   ```bash
   aws secretsmanager describe-secret --secret-id imprecise-ec2-ssh-private-key --region ca-central-1
   ```

### "Permission denied" on existing instances

If you have existing instances created before SSH key setup:

1. The public key is automatically added to new instances via user-data
2. For existing instances, you'll need to manually add the public key:
   ```bash
   # Get public key
   PUBLIC_KEY=$(aws secretsmanager get-secret-value \
     --secret-id imprecise-ec2-ssh-private-key \
     --query 'SecretString' \
     --output text \
     --region ca-central-1 | jq -r '.public_key')
   
   # Use AWS Systems Manager Session Manager (if SSM agent is installed)
   aws ssm start-session --target <instance-id> --region ca-central-1
   
   # Then in the session:
   echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

### Using AWS Systems Manager (Alternative)

If you prefer not to use SSH keys, you can use AWS Systems Manager Session Manager:

1. The IAM instance profile already includes SSM permissions
2. Install SSM agent in user-data (add to user-data script):
   ```bash
   snap install amazon-ssm-agent --classic
   systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
   systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
   ```

3. Use SSM commands instead of SSH in the workflow

## Next Steps

After setting up SSH keys:
1. The GitHub Actions workflow will automatically use them
2. New EC2 instances will have the public key installed automatically
3. Kamal deployments will work without manual SSH configuration
