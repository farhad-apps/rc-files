#!/bin/bash

sudo apt-get install -y curl jq

# Check if a parameter is provided
if [ $1 -eq 0 ]; then
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
    
    local jq_query=".${path}"
    
    # Use jq to find the value at the constructed path
    if jq -e "$jq_query" "$configs_file_path" > /dev/null; then
        jq -r "$jq_query" "$configs_file_path"
    else
        exit 1
    fi
}

replace_strings() {
  local script="$1"
  local search="$2" 
  local replace="$3"

  sed "s|$search|$replace|g" <<< "$script"
}

setup_ssh(){
    ssh_port=$(get_configs "servers_ssh.port")
    udp_port=$(get_configs "servers_ssh.udp_port")
    api_token=$(get_configs "api_token")
    api_url=$(get_configs "api_url")

    if [ -n "$ssh_port" ]; then
        ssh_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-ssh.sh"
        ssh_script=$(curl -s $ssh_file_url)

        ssh_script=$(replace_strings "$ssh_script" "{apiToken}" "$api_token")
        ssh_script=$(replace_strings "$ssh_script" "{apiUrl}" "$api_url")  
        ssh_script=$(replace_strings "$ssh_script" "{sshPort}" "$ssh_port")
        ssh_script=$(replace_strings "$ssh_script" "{udpPort}" "$udp_port")

        bash -c "$ssh_script" 
    fi
}

setup_openvpn(){
    ovpn_port=$(get_configs "servers_openvpn.port")
    ovpn_domain=$(get_configs "servers_openvpn.domain")
    api_token=$(get_configs "api_token")
    api_url=$(get_configs "api_url")

    if [ -n "$ovpn_port" ]; then
        ovpn_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-openvpn.sh"
        ovpn_script=$(curl -s $ovpn_file_url)

        ovpn_script=$(replace_strings "$ovpn_script" "{apiToken}" "$api_token")
        ovpn_script=$(replace_strings "$ovpn_script" "{apiUrl}" "$api_url")  
        ovpn_script=$(replace_strings "$ovpn_script" "{ovpnPort}" "$ovpn_port")
        ovpn_script=$(replace_strings "$ovpn_script" "{ovpnDomain}" "$ovpn_domain")

        bash -c "$ovpn_script" 
    fi
}

setup_v2ray(){
    vless_tcp_port=$(get_configs "servers_v2ray.vless_tcp_port")
    vmess_tcp_port=$(get_configs "servers_v2ray.vmess_tcp_port")
    api_token=$(get_configs "api_token")
    api_url=$(get_configs "api_url")

    if [ -n "$vless_tcp_port" ]; then
    
        v2ray_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-v2ray.sh"
        v2ray_script=$(curl -s $v2ray_file_url)

        v2ray_script=$(replace_strings "$v2ray_script" "{apiToken}" "$api_token")
        v2ray_script=$(replace_strings "$v2ray_script" "{apiUrl}" "$api_url")  
        v2ray_script=$(replace_strings "$v2ray_script" "{vlessTcpPort}" "$vless_tcp_port")
        v2ray_script=$(replace_strings "$v2ray_script" "{vmessTcpPort}" "$vmess_tcp_port")  

        bash -c "$v2ray_script" 
    fi
}

setup_main(){
    api_token=$(get_configs "api_token")
    api_url=$(get_configs "api_url")
    main_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/main-setup.sh"
    main_content=$(curl -s $main_file_url)
    
    main_content=$(replace_strings "$main_content" "{apiToken}" "$api_token")
    main_content=$(replace_strings "$main_content" "{apiUrl}" "$api_url")  

    bash -c "$main_content" 
}

update_rocket_app(){

    api_token=$(get_configs "api_token")
    api_url=$(get_configs "api_url")

    local file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/rocket-app.js"
    local file_path="/var/rocket-ssh/rocket-app.js"

    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{rapiToken}|$api_token|g" "$file_path"
        sed -i "s|{rapiUrl}|$api_url|g" "$file_path"
    fi

    supervisorctl restart rocketApp
}

# Perform actions based on the parameter
case $action in
    "default-setup")
        setup_main

        ;;
    "setup-ssh")
        setup_ssh

        ;;
    "setup-openvpn")
        setup_openvpn

        ;;
    "setup-v2ray")
        setup_v2ray

        ;;
    "setup-all")
        setup_ssh
        setup_openvpn
        setup_v2ray
        
        ;;
    "update-rocket-app")
        update_rocket_app
        
        ;;
    *)
        echo "Unknown parameter: $param"
        ;;
esac
