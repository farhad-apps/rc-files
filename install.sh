#!/bin/bash

echo "start" > /var/rocket-ssh/status.txt

read_config(){
    config_file="/var/rocket-ssh/rocket_config.txt"

    # Check if the config file exists
    if [ -f "$config_file" ]; then
        # Read the values using grep and awk
        ssh_port=$(grep '^ssh_port=' "$config_file" | awk -F= '{print $2}')
        udp_port=$(grep '^udp_port=' "$config_file" | awk -F= '{print $2}')
        api_token=$(grep '^api_token=' "$config_file" | awk -F= '{print $2}')
        api_url=$(grep '^api_url=' "$config_file" | awk -F= '{print $2}')
        ovpn_enable=$(grep '^ovpn_enable=' "$config_file" | awk -F= '{print $2}')
        ovpn_port=$(grep '^ovpn_port=' "$config_file" | awk -F= '{print $2}')
        ovpn_domain=$(grep '^ovpn_domain=' "$config_file" | awk -F= '{print $2}')
        
        echo "OVPN PORT1: $ovpn_port" 
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
    sudo apt-get update

    # remove packages
    local remove_packages=("supervisor" "nginx")

    for rpackage in "${remove_packages[@]}"; do
        sudo apt-get purge -y "$rpackage"
    done

    # install packages
    local install_packages=("build-essential" "libpam0g-dev" "libcurl4-openssl-dev" "cmake" "net-tools" "curl" "nginx" "nodejs" "supervisor" "psmisc")

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


remove_rocketproc_service(){

    local file_path="/etc/systemd/system/rocketproc.service"
    
    if [ -f "$file_path" ]; then
        sudo systemctl stop rocketproc
        sudo systemctl disable rocketproc
        sudo rm $file_path
        sudo systemctl daemon-reload
    fi
}


complete_install(){
    echo "complete" > /var/rocket-ssh/status.txt

    sudo systemctl restart ssh
    sudo systemctl restart sshd
    
    local conf_file_path="/var/rocket-ssh/rocket_config.txt"
    if [ -f "$so_file_path" ]; then
        rm $conf_file_path
    fi

    local nethogs_folder_path="/var/rocket-ssh/nethogs-json-master"
    if [ -d "$nethogs_folder_path" ]; then
        rm -R $nethogs_folder_path
    fi

    sudo systemctl stop cron
    local coron_file_path="/var/rocket-ssh/cronjob.sh"
    if [ -f "$coron_file_path" ]; then
        pkill -f /var/rocket-ssh/cronjob.sh 
        rm $coron_file_path
        rm /var/rocket-ssh/cronjob.lock
    fi
    
    local ssh_auth_file="/var/rocket-ssh/rocket_ssh_auth.so"
    if [ -f "$ssh_auth_file" ]; then
        rm $ssh_auth_file
    fi
    
    local ovpn_file="/var/rocket-ssh/ovpn-setup.sh"
    if [ -f "$ovpn_file" ]; then
        echo "S"
        #rm $ovpn_file
    fi

    sleep 5
    
    # Remove the script file
    rm /var/rocket-ssh/install
    rm /usr/bin/jcurl.sh
    #rm /var/rocket-ssh/ovpn-setup.sh
}


# Call the functions to perform the tasks
config_needrestart
install_packages
read_config
setup_nethogs
setup_udpgw_service
build_pam_file
config_pam_auth
config_sshd
configure_nginx
remove_rocketproc_service
configure_rocket_app
configure_supervisor
ovpn_installer
complete_install
