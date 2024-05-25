#!/bin/bash

api_token="{apiToken}"
api_url="{apiUrl}"

# Function to check and update needrestart configuration

config_needrestart() {

    local nrconf_file="/etc/needrestart/needrestart.conf"
    
    if [ -e "$nrconf_file" ]; then
        echo '$nrconf{restart} = "a";' >> "$nrconf_file"
    fi

}

install_packages() {

    sudo apt-get update -y
    sudo apt-get purge -y supervisor nginx
    sudo apt-get install -y nginx nodejs supervisor psmisc zip unzip wget curl

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

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;

        proxy_pass http://127.0.0.1:3000/;
        proxy_redirect off;
    }
}
ENDOFFILE

    sudo systemctl restart nginx

}

configure_rocket_app(){

    local file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/rocket-app.js"
    # Define the name of the file you want to create
    local file_path="/var/rocket-ssh/rocket-app.js"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{rapiToken}|$api_token|g" "$file_path"
        sed -i "s|{rapiUrl}|$api_url|g" "$file_path"
    fi
 
}

configure_supervisor(){

    sudo supervisorctl stop rocketApp

    local s_file_path="/etc/supervisor/supervisord.conf"

    echo  "\n[inet_http_server]" >> "$s_file_path"
    echo  "port=*:9001" >> "$s_file_path"
    echo  "username=rocket" >> "$s_file_path"
    echo  "password=rocket_ssh" >> "$s_file_path"

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

setup_bbr(){
    
    wget -N --no-check-certificate https://raw.githubusercontent.com/farhad-apps/rc-files/main/bbr.sh && chmod +x bbr.sh && bash bbr.sh
}


complete_install(){
    
    local api_address="$api_url/confirm-installed?token=$api_token&setup=main"
    response=$(curl -s "$api_address")
}

config_needrestart
install_packages
configure_nginx
configure_rocket_app
configure_supervisor
setup_bbr
complete_install
