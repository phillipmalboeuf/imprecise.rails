# Branch-Based Deployment Setup

This repository is configured to automatically deploy each git branch to its own Ubuntu server on AWS.

## Architecture

- **One EC2 instance per branch**: Each git branch gets its own Ubuntu 22.04 LTS server
- **Automatic deployment**: Pushing to any branch triggers a GitHub Actions workflow
- **Kamal-based deployment**: Uses Kamal for containerized Rails deployment
- **RDS PostgreSQL**: All branches share the same RDS PostgreSQL instance (with separate databases)
- **Secure secrets**: RAILS_MASTER_KEY is stored in AWS Secrets Manager

## Prerequisites

1. AWS Account with appropriate permissions
2. GitHub repository with Actions enabled
3. RDS PostgreSQL instance (already created: `postgres-standard`)
4. RAILS_MASTER_KEY stored in AWS Secrets Manager

## Initial Setup

### 1. Run Infrastructure Setup Script

```bash
./scripts/setup-aws-infrastructure.sh
```

This script will:
- Create IAM roles for EC2 instances and GitHub Actions
- Set up OIDC authentication for GitHub Actions
- Create instance profile for EC2
- Store RAILS_MASTER_KEY in AWS Secrets Manager

### 2. Configure GitHub Secrets

Add the following secret to your GitHub repository:

- **AWS_DEPLOY_ROLE_ARN**: The ARN of the IAM role for GitHub Actions (output from setup script)

Go to: Settings → Secrets and variables → Actions → New repository secret

### 3. Store RAILS_MASTER_KEY

If you haven't already, store your master key in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name imprecise-rails-master-key \
  --secret-string "YOUR_MASTER_KEY_HERE" \
  --region ca-central-1
```

Or update an existing secret:

```bash
aws secretsmanager update-secret \
  --secret-id imprecise-rails-master-key \
  --secret-string "YOUR_MASTER_KEY_HERE" \
  --region ca-central-1
```

## How It Works

### Automatic Deployment

1. **Push to any branch** → GitHub Actions workflow triggers
2. **Workflow checks** if an EC2 instance exists for that branch
3. **Creates instance** if it doesn't exist (or starts it if stopped)
4. **Deploys application** using Kamal with branch-specific configuration
5. **Application accessible** at `http://<instance-ip>`

### Branch Naming

- Branch names are sanitized for use in resource names (e.g., `feature/new-ui` → `feature-new-ui`)
- Each branch gets:
  - EC2 instance: `imprecise-<sanitized-branch>`
  - Security group: `imprecise-<sanitized-branch>-sg`
  - Database: `imprecise_<sanitized-branch>_production`
  - Deploy config: `config/deploy.<sanitized-branch>.yml`

### Instance Configuration

- **AMI**: Ubuntu 22.04 LTS (latest)
- **Instance Type**: t3.micro (can be changed in workflow)
- **Security**: SSH (port 22), HTTP (port 80), HTTPS (port 443)
- **IAM Role**: `imprecise-deploy-instance-profile` (for Secrets Manager access)

## Manual Deployment

You can also trigger deployment manually:

1. Go to Actions tab in GitHub
2. Select "Deploy Branch to AWS" workflow
3. Click "Run workflow"
4. Select the branch to deploy

## Accessing Your Application

After deployment, find your instance IP:

1. Check the GitHub Actions workflow output
2. Or query AWS:

```bash
BRANCH="main"  # or your branch name
SANITIZED=$(echo "$BRANCH" | sed 's/\//-/g' | tr '[:upper:]' '[:lower:]')

aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=imprecise-$SANITIZED" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region ca-central-1
```

Then access: `http://<instance-ip>`

## Database Setup

Each branch gets its own database on the shared RDS instance. The database name follows the pattern:
`imprecise_<sanitized_branch>_production`

To set up the database for a new branch:

```bash
# SSH into the instance
ssh ubuntu@<instance-ip>

# Run migrations
docker exec -it <container-name> bin/rails db:create db:migrate
```

Or add this to your deployment workflow if needed.

## Managing Instances

### List All Branch Instances

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=imprecise" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table \
  --region ca-central-1
```

### Stop an Instance

```bash
INSTANCE_ID="i-xxxxx"
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region ca-central-1
```

### Start an Instance

```bash
INSTANCE_ID="i-xxxxx"
aws ec2 start-instances --instance-ids $INSTANCE_ID --region ca-central-1
```

### Terminate an Instance (when branch is deleted)

```bash
INSTANCE_ID="i-xxxxx"
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region ca-central-1
```

## Cost Management

- **t3.micro instances**: ~$7-10/month per instance (when running)
- **Stopped instances**: Only storage costs (~$0.10/month)
- **RDS**: Shared across all branches (already set up)
- **Consider**: Stopping instances for inactive branches to save costs

## Troubleshooting

### Deployment Fails

1. Check GitHub Actions logs
2. Verify AWS credentials and IAM roles
3. Ensure RAILS_MASTER_KEY is in Secrets Manager
4. Check EC2 instance logs: `ssh ubuntu@<ip> sudo tail -f /var/log/user-data.log`

### Application Not Accessible

1. Check security group allows HTTP (port 80)
2. Verify instance is running
3. Check application logs: `ssh ubuntu@<ip> docker logs <container-name>`

### Database Connection Issues

1. Verify RDS security group allows connections from EC2
2. Check database credentials in deploy config
3. Ensure database exists for the branch

## Security Notes

- **RAILS_MASTER_KEY**: Stored securely in AWS Secrets Manager
- **SSH Access**: Currently open to 0.0.0.0/0 (consider restricting)
- **Database**: Each branch has isolated database
- **Secrets**: Never commit master.key to git (already in .gitignore)

## Next Steps

1. Run the infrastructure setup script
2. Add GitHub secret
3. Push to a branch to trigger first deployment
4. Monitor costs and stop unused instances
