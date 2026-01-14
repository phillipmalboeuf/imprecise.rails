#!/bin/bash
# EC2 User Data script for initial instance setup

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install basic tools
apt-get install -y \
  curl \
  wget \
  git \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Kamal
curl -fsSL https://github.com/basecamp/kamal/releases/latest/download/kamal-linux-amd64 -o /usr/local/bin/kamal
chmod +x /usr/local/bin/kamal

# Install PostgreSQL client
apt-get install -y postgresql-client

# Configure automatic security updates
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# Create app directory
mkdir -p /home/ubuntu/app
chown ubuntu:ubuntu /home/ubuntu/app

# Log completion
echo "EC2 instance setup completed at $(date)" >> /var/log/user-data.log
