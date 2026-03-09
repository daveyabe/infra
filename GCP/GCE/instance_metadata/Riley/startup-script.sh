#! /bin/bash
USER_DIR=/home/ubuntu
RUNNER_DIR=/home/ubuntu/actions-runner
URL=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/gh-url -H "Metadata-Flavor: Google")
TOKEN=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/gh-token -H "Metadata-Flavor: Google")
LABELS=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/labels -H "Metadata-Flavor: Google")
HOSTNAME=$(hostname)
# Update the apt package index and install necessary packages
apt-get update && sudo apt-get -y upgrade
apt-get install -y ca-certificates curl gnupg lsb-release tar jq

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add the Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update apt package index again with the new repository
apt-get update -y

# Install Docker Engine and the Docker Compose plugin
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ensure the Docker service starts automatically on boot (default behavior on most modern Linux distros)
systemctl enable docker

# Optional: Add the default 'docker' group to allow running docker without sudo
# Replace 'your-username' with the actual username you use to SSH into the VM.
# Note: The username might not be available during the startup script execution,
# but it will be applied upon the user's first login.
usermod -aG docker ubuntu

#grab the runner - version locked
cd $USER_DIR
curl -o actions-runner-linux-x64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-x64-2.331.0.tar.gz
mkdir actions-runner
tar xzf ./actions-runner-linux-x64-2.331.0.tar.gz -C actions-runner
chown -R ubuntu:ubuntu /home/ubuntu/actions-runner

REPO_PATH=$(echo "$URL" | sed 's|https://github.com/||')
RUNNER_TOKEN=$(curl -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/repos/${REPO_PATH}/actions/runners/registration-token"| jq -r '.token')

# Configure and Install Service as Ubuntu User
sudo -u ubuntu $RUNNER_DIR/config.sh --url $URL --token $RUNNER_TOKEN --name gcp-$HOSTNAME --labels $LABELS --unattended --replace
cd $RUNNER_DIR
./svc.sh install ubuntu
./svc.sh start
#removal
#sudo ./svc.sh uninstall
#./config.sh remove --token PROVIDED-BY-GITHUB