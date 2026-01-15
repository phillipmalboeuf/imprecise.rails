# Dokku Deployment Setup

This project uses GitHub Actions to automatically deploy branches to Dokku instances running on AWS EC2.

## Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:

### AWS Configuration

1. **`AWS_ACCESS_KEY_ID`** - AWS access key ID for EC2 operations
2. **`AWS_SECRET_ACCESS_KEY`** - AWS secret access key
3. **`AWS_REGION`** (optional) - AWS region, defaults to `us-east-1`
4. **`DOKKU_AMI_ID`** - AMI ID of your pre-configured Dokku image
   - Find your AMI ID by name: `aws ec2 describe-images --filters "Name=name,Values=dokku" --query 'Images[0].ImageId' --output text`

### EC2 Instance Configuration (Optional)

5. **`AWS_INSTANCE_TYPE`** (optional) - EC2 instance type, defaults to `t3.small`
6. **`AWS_KEY_PAIR_NAME`** (optional) - EC2 key pair name for SSH access
7. **`AWS_SECURITY_GROUP_ID`** (optional) - Security group ID for the instances
   - Should allow inbound SSH (port 22) and HTTP/HTTPS (ports 80, 443)
8. **`AWS_SUBNET_ID`** (optional) - Subnet ID for launching instances

### Dokku Configuration

9. **`DOKKU_SSH_PRIVATE_KEY`** - Private SSH key for connecting to Dokku instances
   - Generate with: `ssh-keygen -t ed25519 -C "github-actions" -f dokku_deploy_key`
   - The corresponding public key should be added to your Dokku AMI

10. **`DOKKU_SSH_PUBLIC_KEY`** - Public SSH key (corresponding to the private key above)
    - Used to configure Dokku's SSH access

11. **`DOKKU_DOMAIN`** - Base domain for deployments
    - Example: `example.com`
    - Main branch will use this domain
    - Other branches will use `branch-name.example.com`

12. **`RAILS_MASTER_KEY`** (optional but recommended) - Rails master key for production
    - Copy from `config/master.key` or generate a new one

13. **`LETSENCRYPT_EMAIL`** (required for SSL) - Email address for Let's Encrypt certificate notifications
    - Used for certificate expiration warnings and account recovery
    - Example: `your-email@example.com`

14. **`GITHUB_SSH_PUBLIC_KEY`** (optional) - Public SSH key if Dokku needs to pull from private GitHub repos
    - Only needed if you're using private repositories that Dokku needs to access

## How It Works

1. **On push to any branch:**
   - The workflow checks if an EC2 instance exists for that branch (by tag)
   - If not, launches a new EC2 instance from your Dokku AMI
   - Waits for the instance to be ready (Dokku is already installed in the AMI)
   - Creates a sanitized app name from the branch name
   - Checks if a Dokku app exists for that branch
   - If not, creates a new Dokku app
   - Sets up PostgreSQL database (if plugin is installed)
   - Configures the domain
   - Pushes the code to Dokku
   - Runs database migrations

2. **Instance Naming:**
   - Instances are tagged with `Name=dokku-{branch-name}` and `Branch={branch-name}`
   - Branch names are sanitized (lowercase, special chars replaced with hyphens)

3. **App Naming:**
   - Branch names are sanitized (lowercase, special chars replaced with hyphens)
   - Example: `feature/new-ui` → app name: `feature-new-ui`

4. **Domain Configuration:**
   - Main/master branch: Uses `DOKKU_DOMAIN` directly
   - Other branches: Uses `branch-name.DOKKU_DOMAIN`

5. **SSL/HTTPS Configuration:**
   - Uses Dokku Let's Encrypt plugin for SSL certificates
   - SSL termination handled directly by Dokku
   - Certificates are automatically issued and renewed by Let's Encrypt
   - HTTP (port 80) automatically redirects to HTTPS (port 443)
   - Each branch gets its own SSL certificate

## Finding Your Dokku AMI

Since you already have a Dokku AMI created, you just need to find its ID:

1. **Find AMI by name:**
   ```bash
   aws ec2 describe-images \
     --filters "Name=name,Values=dokku" \
     --query 'Images[0].[ImageId,Name,CreationDate]' \
     --output table \
     --region YOUR_REGION
   ```

2. **Or list all your AMIs:**
   ```bash
   aws ec2 describe-images \
     --owners self \
     --query 'Images[*].[ImageId,Name,CreationDate]' \
     --output table \
     --region YOUR_REGION
   ```

3. **Copy the AMI ID and set it in your `DOKKU_AMI_ID` secret**

## SSL/HTTPS Setup

This deployment uses **Dokku Let's Encrypt plugin** for SSL certificates, with SSL termination handled directly by Dokku.

### How It Works

1. **Dokku Let's Encrypt plugin** is automatically installed if not present
2. **Let's Encrypt certificate** is requested for each domain
3. **Dokku nginx** handles SSL termination and HTTP→HTTPS redirect
4. **Route 53 DNS** points directly to EC2 instance IP (A record)
5. **EC2 Security Group** is automatically configured to allow HTTP (80) and HTTPS (443) from anywhere

### Benefits

- ✅ Free SSL certificates from Let's Encrypt
- ✅ Automatic certificate renewal (handled by Dokku)
- ✅ Simple setup - no load balancer needed
- ✅ HTTP to HTTPS redirect handled by Dokku
- ✅ Direct connection to EC2 instance

### Requirements

- **Route 53 hosted zone** must exist for your domain
- **LETSENCRYPT_EMAIL** secret must be set (for certificate notifications)
- **EC2 instance** must have a public IP address
- The workflow automatically handles Let's Encrypt setup and DNS configuration

## Security Group Configuration

Your EC2 security group should allow:
- **Inbound SSH (port 22)** from GitHub Actions IPs or your IP
- **Inbound HTTP (port 80)** from anywhere (0.0.0.0/0) - automatically configured by the workflow
- **Inbound HTTPS (port 443)** from anywhere (0.0.0.0/0) - automatically configured by the workflow

**Note:** The workflow automatically configures HTTP and HTTPS access to allow Let's Encrypt validation and direct access to your application.

### Finding or Creating a Security Group

You have two options:

#### Option 1: Use an Existing Security Group

1. **List your existing security groups:**
   ```bash
   aws ec2 describe-security-groups \
     --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
     --output table \
     --region YOUR_REGION
   ```

2. **Check if it has the required rules:**
   ```bash
   aws ec2 describe-security-groups \
     --group-ids sg-xxxxxxxxx \
     --query 'SecurityGroups[0].IpPermissions[*].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
     --output table \
     --region YOUR_REGION
   ```

3. **If SSH (port 22) is missing, add it:**
   
   **Option A: Use the helper script (recommended):**
   ```bash
   export AWS_SECURITY_GROUP_ID=sg-xxxxxxxxx
   ./scripts/add-ssh-access.sh
   ```
   
   **Option B: Manual command:**
   ```bash
   # Get your current IP
   MY_IP=$(curl -s https://checkip.amazonaws.com)
   
   # Add SSH access from your IP
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxxxxxx \
     --protocol tcp \
     --port 22 \
     --cidr $MY_IP/32 \
     --region YOUR_REGION
   
   # Or allow from anywhere (for GitHub Actions CI/CD)
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxxxxxx \
     --protocol tcp \
     --port 22 \
     --cidr 0.0.0.0/0 \
     --region YOUR_REGION
   ```

#### Option 2: Create a New Security Group

1. **Create a new security group:**
   ```bash
   aws ec2 create-security-group \
     --group-name dokku-build-sg \
     --description "Security group for Dokku deployments" \
     --region YOUR_REGION
   ```
   
   This will return a GroupId (e.g., `sg-0123456789abcdef0`)

2. **Add SSH access (from your current IP):**
   ```bash
   MY_IP=$(curl -s https://checkip.amazonaws.com)
   
   aws ec2 authorize-security-group-ingress \
     --group-id sg-0123456789abcdef0 \
     --protocol tcp \
     --port 22 \
     --cidr $MY_IP/32 \
     --region YOUR_REGION
   ```

3. **Add HTTP access (for web traffic):**
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-0123456789abcdef0 \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0 \
     --region YOUR_REGION
   ```

4. **Add HTTPS access (for secure web traffic):**
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-0123456789abcdef0 \
     --protocol tcp \
     --port 443 \
     --cidr 0.0.0.0/0 \
     --region YOUR_REGION
   ```

5. **Use the GroupId in your script:**
   ```bash
   export AWS_SECURITY_GROUP_ID=sg-0123456789abcdef0
   ```

**Note:** For deployment, you need SSH (port 22) access for GitHub Actions. HTTP/HTTPS ports are needed when you deploy applications to the instances.

## IAM Permissions

The AWS credentials need the following permissions:
- `ec2:DescribeInstances`
- `ec2:RunInstances`
- `ec2:StartInstances`
- `ec2:StopInstances`
- `ec2:CreateTags`
- `ec2:DescribeImages`

## Troubleshooting

### SSH Permission Denied (publickey)

If you get `Permission denied (publickey)` when trying to SSH:

1. **Check which key pair was used on the instance:**
   ```bash
   aws ec2 describe-instances \
     --instance-ids i-xxxxxxxxx \
     --query 'Reservations[0].Instances[0].KeyName' \
     --output text
   ```

2. **Find your private key file:**
   ```bash
   # List your key pairs in AWS
   aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table
   
   # Find the matching private key file (usually in ~/.ssh/)
   ls -la ~/.ssh/
   ```

3. **Verify the key file matches:**
   - The key pair name in AWS should match (or be related to) your private key filename
   - Common patterns: `my-key` in AWS → `~/.ssh/my-key` or `~/.ssh/my-key.pem`

4. **Set the correct key pair name:**
   ```bash
   export AWS_KEY_PAIR_NAME=your-actual-key-pair-name
   ```

5. **Or use the full path to the private key:**
   ```bash
   export AWS_KEY_PAIR_NAME=/path/to/your/private-key.pem
   ```

### Other Common Issues

- **Instance launch fails:** Check AMI ID, instance type, and IAM permissions
- **SSH connection timeout:** Verify security group allows SSH (port 22) from your IP
- **SSH connection fails:** Check key pair configuration (see above)
- **Dokku not ready:** The script waits up to 10 minutes for Dokku installation. Check user data script logs
- **App creation fails:** Check that the app name is valid (starts with letter, no special chars)
- **Domain not working:** Verify DNS is configured to point to your EC2 instance's public IP
- **Database connection fails:** Ensure PostgreSQL plugin is installed and database is linked
