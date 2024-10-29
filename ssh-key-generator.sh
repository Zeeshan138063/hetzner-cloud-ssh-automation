#!/bin/bash

create_ssh_key() {
  # Initialize variables with improved naming
  local ssh_key_name ssh_key_email ssh_user_name key_type host_ip

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

  # Parse the key parameters with improved argument names
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --key-name) ssh_key_name="$2"; shift ;;
      --email) ssh_key_email="$2"; shift ;;
      --user) ssh_user_name="$2"; shift ;;
      --type) key_type="$2"; shift ;;  # Retained for Hetzner server type
      --host-ip) host_ip="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; return 1 ;;
    esac
    shift
  done

  # Prompt for any missing values
  prompt_if_empty "ssh_key_name" "Please enter the name for the SSH key"
  prompt_if_empty "ssh_key_email" "Please enter the email for the SSH key"
  prompt_if_empty "ssh_user_name" "Please enter the username for SSH connection"
  prompt_if_empty "key_type" "Please enter the Hetzner server type"
  prompt_if_empty "host_ip" "Please enter the IP address of the host"

  # Final check for any unset variables
  if [ -z "$ssh_key_name" ] || [ -z "$ssh_key_email" ] || [ -z "$ssh_user_name" ] || [ -z "$key_type" ] || [ -z "$host_ip" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: create_ssh_key --key-name <name> --email <email> --user <username> --type <Hetzner server type> --host-ip <IP>"
    return 1
  fi

  # Set the directory path for SSH keys with explicit $HOME path
  local ssh_keys_dir="${HOME}/ssh-keys"  # Explicitly use $HOME instead of ~

  # Create the directory if it doesn't exist, with error handling
  mkdir -p "$ssh_keys_dir"
  if [ $? -ne 0 ]; then
    echo "Error: Could not create directory at $ssh_keys_dir."
    return 1
  fi

  echo "SSH keys will be stored in: $ssh_keys_dir"

  # Prompt for a passphrase or use default if not provided
  local passphrase="zaviyar"  # Set default passphrase
  read -p "Enter a passphrase for the SSH key (or press Enter to use default): " user_passphrase
  passphrase="${user_passphrase:-$passphrase}"

  # Generate the SSH key pair using ED25519 algorithm
  ssh-keygen -t ed25519 -C "$ssh_key_email" -f "$ssh_keys_dir/$ssh_key_name" -N "$passphrase"
  if [ $? -ne 0 ]; then
    echo "Error: SSH key generation failed."
    return 1
  fi

  echo "ED25519 SSH key pair created successfully at: $ssh_keys_dir/$ssh_key_name and $ssh_keys_dir/$ssh_key_name.pub"

  # Aliases to be added to ~/.my_custom_commands
  local custom_commands_file="${HOME}/.my_custom_commands"

  # Ensure the file exists and append aliases
  echo "" >> "$custom_commands_file"
  echo "# Key for ${key_type}" >> "$custom_commands_file"
  echo "alias start${key_type}=\"ssh-add ${ssh_keys_dir}/${ssh_key_name}\"" >> "$custom_commands_file"
  echo "alias connectwith${key_type}=\"ssh-add ${ssh_keys_dir}/${ssh_key_name} && ssh ${ssh_user_name}@${host_ip}\"" >> "$custom_commands_file"
  echo "" >> "$custom_commands_file"

  # Inform the user of the aliases created
  echo "Aliases created:"
  echo "start${key_type}: Adds the SSH key using 'ssh-add'"
  echo "connectwith${key_type}: Adds the SSH key and connects to ${ssh_user_name}@${host_ip} in one command"

  # Source the file so that the new aliases are available immediately
  source "$custom_commands_file"

  # Display the public key so it can be copied
  local pub_key_file="${ssh_keys_dir}/${ssh_key_name}.pub"
  echo "Here is your public SSH key:"
  cat "$pub_key_file"

  # Attempt to copy the public key to clipboard, depending on the OS
  if command -v pbcopy &>/dev/null; then
    cat "$pub_key_file" | pbcopy
    echo "Public key has been copied to clipboard (macOS)."
  elif command -v xclip &>/dev/null; then
    cat "$pub_key_file" | xclip -selection clipboard
    echo "Public key has been copied to clipboard (Linux with xclip)."
  else
    echo "Note: Clipboard copy not supported on this system. Please copy the key manually."
  fi

  return 0  # Return success
}

# Call the function
create_ssh_key
