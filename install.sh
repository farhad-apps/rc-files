#!/bin/bash

configs_file_path="/var/rocket-ssh/configs.json"


start_installtion(){
    echo "start" > /var/rocket-ssh/status.txt
}

get_config() {
    local key_to_extract="$1"

    # Check if jq is installed
    if command -v jq &> /dev/null; then
        exit 0
        return 1
    fi

    # Use jq to parse the JSON file and print the value of the specified key
    local value=$(jq -r --arg key "$key_to_extract" '.[$key]?' "$configs_file_path")

    # Check if the key was found
    if [ -z "$value" ]; then
        return 1
    else
        echo "$value"
        return 0
    fi
}

# Function to check and update needrestart configuration
config_needrestart() {
    local nrconf_file="/etc/needrestart/needrestart.conf"
    
    if [ -e "$nrconf_file" ]; then
        echo '$nrconf{restart} = "a";' >> "$nrconf_file"
    fi

}

# Function to install required packages
install_packages() {
    sudo apt-get update -y
    
    # remove packages
    local remove_packages=("supervisor" "nginx")

    for rpackage in "${remove_packages[@]}"; do
        sudo apt-get purge -y "$rpackage"
    done

    # install packages
    local install_packages=("jq" "build-essential" "libpam0g-dev" "libcurl4-openssl-dev" "cmake" "net-tools" "curl" "nginx" "nodejs" "supervisor" "psmisc" "unzip")

    for ipackage in "${install_packages[@]}"; do
        sudo apt-get install -y "$ipackage"
    done

}

configure_nginx(){
    cat > /etc/nginx/sites-available/default << ENDOFFILE
server {
    listen 0.0.0.0;
    server_name localhost;

    location /papi {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_set_header X-NginX-Proxy true;

        proxy_pass http://127.0.0.1:3000/;
        proxy_redirect off;
    }
}
ENDOFFILE

    sudo systemctl restart nginx

}

configure_rocket_app(){

    local file_url="https://raw.githubusercontent.com/farhad-apps/files/main/rocket-app.js"
    # Define the name of the file you want to create
    local file_path="/var/rocket-ssh/rocket-app.js"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then
        local api_token=$(get_config "api_token")
        local api_url=$(get_config "api_url")
        sed -i "s|{api_token}|$api_token|g" "$file_path"
        sed -i "s|{api_url}|$api_url|g" "$file_path"
    fi
 
}

configure_supervisor(){
    sudo supervisorctl stop rocketApp

    local s_file_path="/etc/supervisor/supervisord.conf"

    local content="\n[inet_http_server]\nport=*:9001\nusername=rocket\npassword=rocket_ssh"

    # Append content to the file    
    echo -e "$content" | sudo tee -a "$s_file_path" > /dev/null

    local rocket_file_path="/etc/supervisor/conf.d/rocket_app.conf"

    cat > $rocket_file_path << ENDOFFILE
[program:rocketApp]
command=/usr/bin/node /var/rocket-ssh/rocket-app.js
autostart=true
autorestart=true
startretries=3
user=root
ENDOFFILE

    sudo service supervisor restart
    sudo supervisorctl start rocketApp
}


complete_install(){
  echo "complete" > /var/rocket-ssh/status.txt
}


# Call the functions to perform the tasks
config_needrestart
install_packages
configure_nginx
configure_rocket_app
configure_supervisor
complete_install
