#!/bin/bash
set -e

# Variables #################################
# Version of CoreDNS to use
COREDNS_VERSION=1.2.2
# Backend DNS servers to proxy; format "<ip_address>:<port>"
DNS_SERVER1=140.107.42.11:53
DNS_SERVER2=140.107.117.11:53
#############################################

# install Git and Wget
echo -e "\nInstalling dependencies (git and wget)..."
apt -qq update 
apt -y -qq install git wget

# Create the unprivileged coredns user
echo -e "\nCreating coredns user..."
useradd -m -d /var/lib/coredns --shell /bin/false coredns

# Download and install CoreDNS
echo -e "\nDownloading and installing CoreDNS..."
wget -q  https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_amd64.tgz
tar xf coredns_${COREDNS_VERSION}_linux_amd64.tgz 
chmod +x coredns
mv coredns /usr/local/bin/

# Download blacklist 
echo -e "\nDownloading blacklist..."
mkdir -p /etc/coredns
git clone -q https://github.com/StevenBlack/hosts.git /etc/coredns/hosts

# Create CoreDNS configuration
echo "Configuring CoreDNS..."
cat > /etc/coredns/Corefile << EOL
.:53 {
    prometheus 0.0.0.0:9153
    bind 0.0.0.0 
    hosts /etc/coredns/hosts/hosts {
      fallthrough
    }
    proxy . ${DNS_SERVER1} ${DNS_SERVER2}
}
EOL

# Create Systemd configuration
echo -e "\nConfiguring systemd..."
cat > /lib/systemd/system/coredns.service << EOL
[Unit]
Description=CoreDNS DNS server
Documentation=https://coredns.io
After=network.target

[Service]
PermissionsStartOnly=true
LimitNOFILE=1048576
LimitNPROC=512
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
User=coredns
WorkingDirectory=~
ExecStart=/usr/local/bin/coredns -conf=/etc/coredns/Corefile
ExecReload=/bin/kill -SIGUSR1 \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

# Enable and start CoreDNS
systemctl daemon-reload
systemctl start coredns.service
systemctl enable coredns.service
systemctl --no-pager status coredns.service

# Create cron job to update black list
echo -e "\nInstalling blacklist update cron job..."
cat > /etc/cron.d/coredns-blacklist-update << EOL
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 */6 * * *  root    cd /etc/coredns/hosts && git pull > /dev/null 2>&1
EOL

# Cleanup
echo -e "\nCleaning up..."
rm coredns_${COREDNS_VERSION}_linux_amd64.tgz

echo -e "\nDone!!!"
