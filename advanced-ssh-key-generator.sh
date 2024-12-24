#!/bin/bash

# Advanced SSH Key Generator and Cloud Config Creator
# This script:
# 1. Generates ED25519 SSH keys
# 2. Creates convenient aliases for SSH connections
# 3. Generates a secure cloud-init configuration
# 4. Handles clipboard operations for different OS types
# 5. Provides detailed error handling and logging

create_advanced_ssh_key() {
  # Initialize all variables
  local ssh_key_name ssh_key_email ssh_user_name key_type host_ip output_config
  local default_config_name="cloud-config.yaml"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local log_file="${script_dir}/ssh_key_gen_${timestamp}.log"

  # Setup logging function
  log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$log_file"
  }

  # Helper function to prompt for input if missing
  prompt_if_empty() {
    local var_name="$1"
    local prompt_message="$2"
    local default_value="${!var_name}"
    
    if [ -z "$default_value" ]; then
      read -p "$prompt_message: " "$var_name"
      eval "$var_name=\${$var_name}"
    fi
  }

  # Parse command line arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --key-name) ssh_key_name="$2"; shift ;;
      --email) ssh_key_email="$2"; shift ;;
      --user) ssh_user_name="$2"; shift ;;
      --type) key_type="$2"; shift ;;
      --host-ip) host_ip="$2"; shift ;;
      --output-config) output_config="$2"; shift ;;
      --help)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --key-name NAME       Name for the SSH key"
        echo "  --email EMAIL         Email for the SSH key"
        echo "  --user USERNAME       Username for SSH connection"
        echo "  --type TYPE           Server type identifier"
        echo "  --host-ip IP          Host IP address"
        echo "  --output-config FILE  Output path for cloud-config"
        return 0
        ;;
      *) 
        log_message "Unknown parameter passed: $1" "ERROR"
        return 1 
        ;;
    esac
    shift
  done

  # Prompt for any missing required values
  prompt_if_empty "ssh_key_name" "Please enter the name for the SSH key"
  prompt_if_empty "ssh_key_email" "Please enter the email for the SSH key"
  prompt_if_empty "ssh_user_name" "Please enter the username for SSH connection"
  prompt_if_empty "key_type" "Please enter the server type identifier"
  prompt_if_empty "host_ip" "Please enter the IP address of the host"
  
  # Set default output config if not specified
  output_config="${output_config:-${script_dir}/${default_config_name}}"

  # Validate inputs
  if [[ ! "$host_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_message "Invalid IP address format: $host_ip" "ERROR"
    return 1
  fi

  # Set up SSH keys directory
  local ssh_keys_dir="${HOME}/ssh-keys"
  mkdir -p "$ssh_keys_dir" || {
    log_message "Failed to create directory: $ssh_keys_dir" "ERROR"
    return 1
  }

  log_message "SSH keys will be stored in: $ssh_keys_dir"

  # Generate SSH key pair
  local passphrase="zaviyar"
  read -p "Enter a passphrase for the SSH key (or press Enter to use default): " user_passphrase
  passphrase="${user_passphrase:-$passphrase}"

  log_message "Generating ED25519 SSH key pair..."
  ssh-keygen -t ed25519 -C "$ssh_key_email" -f "$ssh_keys_dir/$ssh_key_name" -N "$passphrase" || {
    log_message "SSH key generation failed" "ERROR"
    return 1
  }

  # Create aliases
  local custom_commands_file="${HOME}/.my_custom_commands"
  {
    echo ""
    echo "# Key for ${key_type} (Generated on $(date))"
    echo "alias start${key_type}=\"ssh-add ${ssh_keys_dir}/${ssh_key_name}\""
    echo "alias connectwith${key_type}=\"ssh-add ${ssh_keys_dir}/${ssh_key_name} && ssh ${ssh_user_name}@${host_ip}\""
    echo ""
  } >> "$custom_commands_file"

  # Generate cloud-config
  local pub_key_content
  pub_key_content=$(cat "${ssh_keys_dir}/${ssh_key_name}.pub")
  
  log_message "Generating cloud-config at: $output_config"
  
  cat > "$output_config" << EOL
#cloud-config

# Generated by Advanced SSH Key Generator on $(date)
# For user: ${ssh_user_name}

# Update package lists and upgrade installed packages
package_update: true
package_upgrade: true
apt:
  conf: |
    DPkg::Options {
      "--force-confnew";
      "--force-confdef";
    }
  dpkg_options: ["--allow-downgrades", "--allow-remove-essential", "--allow-change-held-packages"]

# Install essential packages
packages:
  - vim
  - curl
  - wget
  - unzip
  - htop
  - net-tools
  - fail2ban
  - ufw

# Configure timezone
timezone: UTC

# Create user with sudo privileges
users:
  - name: ${ssh_user_name}
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${pub_key_content}

# Security configurations
write_files:
  - path: /etc/needrestart/conf.d/99disable-prompt.conf
    content: |
      \$nrconf{kernelhints} = -1;
    permissions: '0644'

  - path: /etc/fail2ban/jail.local
    content: |
      [DEFAULT]
      bantime = 60000
      findtime = 6000
      maxretry = 3
      banaction = iptables-multiport

      [sshd]
      enabled = true
      port = ssh
      filter = sshd
      logpath = /var/log/auth.log
      maxretry = 3
      bantime = 60000
      findtime = 6000
    permissions: '0644'

# System commands to execute
runcmd:
  # Set up SSH directory and permissions
  - mkdir -p /home/${ssh_user_name}/.ssh
  - echo "${pub_key_content}" > /home/${ssh_user_name}/.ssh/authorized_keys
  - chown -R ${ssh_user_name}:${ssh_user_name} /home/${ssh_user_name}/.ssh
  - chmod 700 /home/${ssh_user_name}/.ssh
  - chmod 600 /home/${ssh_user_name}/.ssh/authorized_keys

  # Configure SSH security
  - sed -i '/PermitRootLogin/d' /etc/ssh/sshd_config
  - echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
  - sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config
  - echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

  # Configure UFW
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ssh
  - ufw allow http
  - ufw allow https
  - ufw --force enable

  # Setup fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban

  # Restart SSH service
  - systemctl restart ssh

  # Schedule a reboot
  - shutdown -r +1 "Server will reboot in 1 minute"

final_message: "Cloud-init setup completed. System will reboot in 1 minute."
EOL

  # Handle clipboard operations
  if command -v pbcopy &>/dev/null; then
    cat "${ssh_keys_dir}/${ssh_key_name}.pub" | pbcopy
    log_message "Public key copied to clipboard (macOS)"
  elif command -v xclip &>/dev/null; then
    cat "${ssh_keys_dir}/${ssh_key_name}.pub" | xclip -selection clipboard
    log_message "Public key copied to clipboard (Linux with xclip)"
  else
    log_message "Clipboard copy not supported on this system" "WARNING"
  fi

  # Final success messages
  log_message "SSH key pair created successfully!"
  log_message "Public key location: ${ssh_keys_dir}/${ssh_key_name}.pub"
  log_message "Private key location: ${ssh_keys_dir}/${ssh_key_name}"
  log_message "Cloud config generated: $output_config"
  log_message "Aliases created: start${key_type}, connectwith${key_type}"
  
  # Source the aliases file
  source "$custom_commands_file"

  return 0
}

# Execute the function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  create_advanced_ssh_key "$@"
fi 