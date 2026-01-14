# Domain Setup Guide

This guide explains how to set up custom domains for your branch-based deployments.

## Domain Structure

- **Main branch**: `impreciseanalysis.com`
- **Other branches**: `<branchname>.impreciseanalysis.com`
  - Example: `feature-new-ui` branch → `feature-new-ui.impreciseanalysis.com`

## Prerequisites

1. You own the domain `impreciseanalysis.com`
2. You have access to your domain registrar
3. AWS account with Route 53 access

## Step 1: Run Domain Setup Script

```bash
./scripts/setup-domain.sh
```

This script will:
- Create a Route 53 hosted zone for your domain
- Request an ACM certificate for the domain and wildcard (`*.impreciseanalysis.com`)
- Create DNS validation records
- Set up IAM permissions for Route 53

### Important Output

The script will output name servers. You **must** update your domain registrar with these:

```
ns-xxx.awsdns-xx.com
ns-xxx.awsdns-xx.org
ns-xxx.awsdns-xx.co.uk
ns-xxx.awsdns-xx.net
```

## Step 2: Update Domain Registrar

1. Log in to your domain registrar (where you bought `impreciseanalysis.com`)
2. Find the DNS/Nameserver settings
3. Replace the existing name servers with the ones from Step 1
4. Save changes

**Note**: DNS propagation can take 24-48 hours, but usually happens within a few hours.

## Step 3: Wait for Certificate Validation

The ACM certificate needs to be validated via DNS. The setup script will:
- Create the validation records in Route 53
- Wait for AWS to validate them

You can check certificate status:

```bash
aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='impreciseanalysis.com' || DomainName=='*.impreciseanalysis.com']"
```

The certificate status should be `ISSUED` before deployments will work with SSL.

## Step 4: Deploy a Branch

Once DNS is configured and the certificate is validated, push to any branch:

```bash
git checkout -b test-domain
git push origin test-domain
```

The GitHub Actions workflow will:
1. Create/update the EC2 instance
2. Create a Route 53 A record pointing to the instance IP
3. Deploy with Kamal's SSL proxy (using Let's Encrypt)
4. Make the app available at `https://test-domain.impreciseanalysis.com`

## How It Works

### DNS Records

Each branch deployment creates an A record in Route 53:
- **Main branch**: `impreciseanalysis.com` → `<instance-ip>`
- **Other branches**: `<branch>.impreciseanalysis.com` → `<instance-ip>`

### SSL/TLS

Kamal uses Traefik as a reverse proxy with Let's Encrypt for automatic SSL certificates:
- SSL certificates are automatically requested and renewed
- HTTPS is enabled by default
- HTTP redirects to HTTPS

### Production Configuration

The Rails app is configured to:
- Assume SSL (since Traefik terminates SSL)
- Force SSL redirects
- Use secure cookies

## Verifying DNS Setup

### Check Name Servers

```bash
dig NS impreciseanalysis.com
```

Should show the AWS Route 53 name servers.

### Check A Records

```bash
# For main branch
dig A impreciseanalysis.com

# For a branch
dig A feature-new-ui.impreciseanalysis.com
```

Should resolve to your EC2 instance IP.

### Check Certificate

```bash
curl -vI https://impreciseanalysis.com
```

Should show a valid SSL certificate.

## Troubleshooting

### DNS Not Resolving

1. **Check name servers**: Verify your registrar has the correct Route 53 name servers
2. **Wait for propagation**: DNS changes can take up to 48 hours
3. **Check Route 53 records**: 
   ```bash
   aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
   ```

### Certificate Not Issued

1. **Check validation records**: Ensure DNS validation records exist in Route 53
2. **Wait**: Certificate validation can take 30-60 minutes
3. **Check certificate status**:
   ```bash
   aws acm describe-certificate --certificate-arn <arn> --region us-east-1
   ```

### SSL Errors

1. **Check Kamal logs**: `ssh ubuntu@<ip> docker logs <container>`
2. **Verify Traefik is running**: Kamal's proxy should be handling SSL
3. **Check domain in Kamal config**: Ensure the domain matches the DNS record

### Domain Not Updating

If you change a branch's instance IP, the DNS record should update automatically. If not:

1. Check GitHub Actions logs for DNS update step
2. Manually update the record:
   ```bash
   aws route53 change-resource-record-sets \
     --hosted-zone-id <zone-id> \
     --change-batch file://change-batch.json
   ```

## Manual DNS Record Management

### Create A Record

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='impreciseanalysis.com.'].[Id]" --output text | cut -d'/' -f3)

cat > change-batch.json << EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "subdomain.impreciseanalysis.com",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "1.2.3.4"}]
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file://change-batch.json
```

### Delete A Record

Change `"Action": "UPSERT"` to `"Action": "DELETE"` in the change batch.

## Cost Considerations

- **Route 53 Hosted Zone**: $0.50/month
- **Route 53 Queries**: $0.40 per million queries (first billion)
- **ACM Certificates**: Free
- **Let's Encrypt**: Free (used by Kamal)

## Security Notes

- **SSL/TLS**: All traffic is encrypted via HTTPS
- **HSTS**: Enabled via `force_ssl` in production config
- **Secure Cookies**: Enabled by default with SSL
- **DNS**: Managed securely in Route 53

## Next Steps

1. Run `./scripts/setup-domain.sh`
2. Update your domain registrar with Route 53 name servers
3. Wait for certificate validation
4. Deploy a branch and verify it's accessible at its domain
