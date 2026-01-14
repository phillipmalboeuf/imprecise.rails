# Custom AMI Setup Guide

This guide explains how to build and use a custom AMI with Docker and Kamal pre-installed, which significantly speeds up instance launches.

## Why Use a Custom AMI?

**Benefits:**
- **Faster launches**: Instances start in ~30 seconds instead of 5-10 minutes
- **More reliable**: No dependency on internet connectivity during launch
- **Consistent**: Same Docker/Kamal versions across all instances
- **Cost efficient**: Less time waiting = less wasted compute time

**What's Pre-installed:**
- Docker CE (latest stable)
- Kamal (latest release)
- PostgreSQL client
- SSM agent
- Base Ubuntu 22.04 LTS packages

## Building the Custom AMI

### Step 1: Run the Build Script

```bash
./scripts/build-custom-ami.sh
```

This script will:
1. Launch a temporary EC2 instance from the latest Ubuntu 22.04 AMI
2. Install Docker, Kamal, and dependencies via user-data
3. Wait for installations to complete
4. Create an AMI from the instance
5. Clean up the temporary instance

**Time**: Approximately 15-20 minutes for the first build

### Step 2: Verify AMI Creation

```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=imprecise-ubuntu-docker-kamal" \
  --region ca-central-1
```

You should see your new AMI with status `available`.

## How It Works

### Automatic AMI Detection

The GitHub Actions workflow automatically:
1. Checks for a custom AMI named `imprecise-ubuntu-docker-kamal`
2. Uses it if available
3. Falls back to base Ubuntu AMI if not found

### Minimal User-Data

With the custom AMI, the user-data script is minimal:
- Sets up SSH keys (if available)
- Creates app directories
- No package installation needed!

## Updating the AMI

When you need to update Docker or Kamal versions:

1. **Rebuild the AMI**:
   ```bash
   ./scripts/build-custom-ami.sh
   ```

2. **The workflow will automatically use the latest AMI** (sorted by creation date)

3. **Old instances**: Continue using the AMI they were launched from (no impact)

## AMI Versioning

The build script creates AMIs with the same name. AWS keeps all versions, and the workflow uses the most recent one.

To see all versions:
```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=imprecise-ubuntu-docker-kamal" \
  --query 'Images[*].[ImageId,CreationDate,State]' \
  --output table \
  --region ca-central-1
```

## Cost Considerations

- **AMI Storage**: ~2-3 GB per AMI version (~$0.10/month per version)
- **Build Instance**: Temporary t3.micro (~$0.01 for 15 minutes)
- **Total**: Negligible cost, significant time savings

## Troubleshooting

### Build Script Fails

1. **Check SSH access**: The script needs SSH access to the build instance
   - Ensure your IP is allowed in the temporary security group
   - Or use SSM Session Manager instead

2. **Check user-data logs**:
   ```bash
   # Get instance IP from build script output
   ssh ubuntu@<instance-ip> 'tail -f /var/log/user-data.log'
   ```

3. **Manual verification**:
   ```bash
   ssh ubuntu@<instance-ip>
   docker --version
   kamal version
   ```

### AMI Not Found

If the workflow can't find the custom AMI:
1. Verify AMI exists: `aws ec2 describe-images --owners self --filters "Name=name,Values=imprecise-ubuntu-docker-kamal"`
2. Check AMI is in the correct region
3. Verify AMI status is `available`

### Instance Launch Fails

If instances fail to launch with the custom AMI:
1. Check AMI permissions (should be available to your account)
2. Verify AMI is in the same region as your instances
3. Check CloudWatch logs for user-data errors

## Manual AMI Creation (Alternative)

If you prefer to build the AMI manually:

1. Launch an instance from Ubuntu 22.04
2. SSH into it
3. Install Docker and Kamal:
   ```bash
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker ubuntu
   
   # Install Kamal
   curl -fsSL https://github.com/basecamp/kamal/releases/latest/download/kamal-linux-amd64 -o /tmp/kamal
   sudo install /tmp/kamal /usr/local/bin/kamal
   
   # Install PostgreSQL client
   sudo apt-get update
   sudo apt-get install -y postgresql-client
   ```

4. Create AMI from the instance:
   ```bash
   aws ec2 create-image \
     --instance-id <instance-id> \
     --name imprecise-ubuntu-docker-kamal \
     --description "Ubuntu 22.04 with Docker and Kamal pre-installed"
   ```

## Next Steps

1. Run `./scripts/build-custom-ami.sh` to create your first custom AMI
2. The next deployment will automatically use it
3. Enjoy faster instance launches! 🚀
