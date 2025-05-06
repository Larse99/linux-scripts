#!/bin/bash
# Author: Lars Eissink
# Really small script to set up a Ansible service user + networking for Debian based systems using Netplan.

# Set constant values
interface="ens18"
ip_address=""
gateway=""
dns=""
search_domains="fqdn.com"

# Prompt for network configuration
read -p "Enter IP address and subnet mask (e.g., 192.168.5.5/24): " ip_address
read -p "Enter gateway address: " gateway
read -p "Enter DNS server address: " dns

# Generate YAML content
yaml_content="network:
  ethernets:
    $interface:
      dhcp4: no
      addresses: [$ip_address]
      nameservers:
        addresses: [$dns]
        search: [$search_domains]
      routes:
        - to: 0.0.0.0/0
          via: $gateway
          metric: 100
          on-link: true"

# Write to the netplan configuration file
config_file="/etc/netplan/01-custom-config.yaml"
echo "$yaml_content" | sudo tee "$config_file" > /dev/null
chmod 0600 $config_file

# Apply the new configuration
netplan apply

echo "Network configuration has been updated and applied."

# Setting Ansible password
read -s -p "Enter a password for the Ansible service user: " ansible_pass
echo "ansible:$ansible_pass" | chpasswd
echo "Ansible service user updated!"

# Updating packages
apt update && apt upgrade -y
