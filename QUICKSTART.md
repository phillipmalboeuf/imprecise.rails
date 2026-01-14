# Quick Start: Branch-Based Deployment

Get your branch-based deployment system up and running in 5 steps.

## Step 1: Store RAILS_MASTER_KEY

```bash
./scripts/store-master-key.sh
```

This will read your `config/master.key` file and store it securely in AWS Secrets Manager.

## Step 2: Set Up AWS Infrastructure

```bash
./scripts/setup-aws-infrastructure.sh
```

This creates:
- IAM roles for EC2 and GitHub Actions
- Instance profile for EC2
- OIDC provider for GitHub Actions

**Important**: Save the `AWS_DEPLOY_ROLE_ARN` output - you'll need it for Step 3.

## Step 3: Configure GitHub Secrets

1. Go to your GitHub repository
2. Navigate to: **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add:
   - **Name**: `AWS_DEPLOY_ROLE_ARN`
   - **Value**: The ARN from Step 2 (e.g., `arn:aws:iam::123456789012:role/imprecise-github-deploy-role`)

## Step 4: Store RDS Password (if needed)

If your RDS instance uses a managed password, it's already in Secrets Manager. Otherwise:

```bash
aws secretsmanager create-secret \
  --name imprecise-rds-password \
  --secret-string "YOUR_RDS_PASSWORD" \
  --region ca-central-1
```

## Step 5: Set Up Domain (Optional but Recommended)

If you want custom domains for your deployments:

```bash
./scripts/setup-domain.sh
```

Then update your domain registrar with the Route 53 name servers shown in the output.

This enables:
- Main branch at `impreciseanalysis.com`
- Other branches at `<branchname>.impreciseanalysis.com`

See [DOMAIN_SETUP.md](./DOMAIN_SETUP.md) for detailed instructions.

## Step 6: Push to a Branch

```bash
git checkout -b test-deployment
git push origin test-deployment
```

The GitHub Actions workflow will automatically:
1. Create an EC2 instance for this branch
2. Create DNS record (if domain is set up)
3. Deploy your application
4. Make it available at:
   - `https://test-deployment.impreciseanalysis.com` (if domain set up)
   - `http://<instance-ip>` (always available)

## Verify Deployment

1. Go to **Actions** tab in GitHub
2. Click on the latest workflow run
3. Check the "Deployment summary" step for:
   - Domain URL (if domain is set up)
   - Instance IP (always available)
4. Visit the URL in your browser:
   - `https://<branch>.impreciseanalysis.com` (if domain set up)
   - `http://<instance-ip>` (always works)

## Troubleshooting

### "Access Denied" errors
- Verify IAM roles were created correctly
- Check GitHub secret is set correctly
- Ensure OIDC provider is configured

### "Secret not found" errors
- Run `./scripts/store-master-key.sh` again
- Verify secret exists: `aws secretsmanager describe-secret --secret-id imprecise-rails-master-key`

### Instance creation fails
- Check your AWS account limits
- Verify you have permissions to create EC2 instances
- Check the GitHub Actions logs for specific errors

## Next Steps

- Read [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed documentation
- Monitor costs in AWS Console
- Stop unused instances to save money
