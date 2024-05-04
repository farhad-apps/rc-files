#!/bin/bash

# Check if a parameter is provided
if [ $# -eq 0 ]; then
    echo "No parameters provided. Please provide a parameter."
    exit 1
fi

# Read the first parameter
action=$1
configs_file_path=/var/rocket-ssh/configs.json

file_exists() {
    local file="$1"
    
    if [ -f "$file" ]; then
        return 0
    else
        return 1
    fi
}

get_configs(){

    local path="$1"

    # Check if the JSON file exists
    if ! file_exists "$configs_file_path"; then
        echo "config file does not exist."
        exit 1
    fi
    
    # Split the path into an array
    IFS='.' read -ra ADDR <<< "$path"
    
    # Initialize the current path with the root of the JSON structure
    local current_path=".${ADDR[0]}"
    
    # Iterate through the rest of the path
    for i in "${ADDR[@]:1}"; do
        current_path=".${current_path}.${i}"
    done
    
    # Use jq to find the value at the constructed path
    if jq -e "$current_path" "$configs_file_path" > /dev/null; then
        jq -r "$current_path" "$configs_file_path"
    else
        echo "Path '$path' not found in"
        exit 1
    fi
}

# Perform actions based on the parameter
case $action in
    "main-setup")
        bash <(curl -Ls https://raw.githubusercontent.com/farhad-apps/rc-files/main/main-setup.sh --ipv4)
        ;;
    "setup-ssh")
        ssh_port=$(get_configs "servers_ssh" "port")
        udp_port=$(get_configs "servers_ssh" "udp_port")
        api_token=$(get_configs "api_token")
        api_url=$(get_configs "api_url")

        file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-ssh.sh"
        file_path="/tmp/rssh"
        curl -s -o "$file_path" "$file_url"

        if [ $? -eq 0 ]; then
            sed -i "s|{apiToken}|$api_token|g" "$file_path"
            sed -i "s|{apiUrl}|$api_url|g" "$file_path"
            sed -i "s|{sshPort}|$ssh_port|g" "$file_path"
            sed -i "s|{udpPort}|$udp_port|g" "$file_path"
            bash /tmp/rssh > /var/rocket-ssh/install-ssh.log 2>&1 &
        fi

        ;;
    "setup-openvpn")
        ovpn_port=$(get_configs "servers_openvpn" "port")
        

        ;;
    "setup-v2ray")
        ovpn_port=$(get_configs "servers_openvpn" "port")
        
        ;;
    *)
        echo "Unknown parameter: $param"
        ;;
esac
