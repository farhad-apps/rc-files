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
    sudo ufw disable
    
    if command -v supervisord >/dev/null 2>&1; then
        echo "Supervisor is installed. Proceeding with uninstallation."
        
        sudo apt-get purge -y supervisor
        
        if [ -d /var/log/supervisor ]; then
            sudo rm -rf /var/log/supervisor/
        fi
        
        if [ -d /etc/supervisor ]; then
            sudo rm -rf /etc/supervisor/
        fi
    fi
    
    sudo apt-get install -y nodejs supervisor psmisc zip unzip wget curl

    if ! command -v nginx >/dev/null 2>&1; then
        sudo apt-get install -y nginx
    fi

}

configure_nginx(){
    ROCKET_FILE="/etc/nginx/sites-available/rocket"

    if [ ! -e "$ROCKET_FILE" ]; then

        cat > /etc/nginx/sites-available/default << ENDOFFILE
server {
    listen 80;
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

server {
    listen 8443;
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
    
    else
        sudo tee /etc/nginx/sites-available/srocket <<'EOF'
server {
    listen 8443;
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

EOF
    sudo ln -s /etc/nginx/sites-available/srocket /etc/nginx/sites-enabled/

    fi

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

    local s_file_path="/etc/supervisor/supervisord.conf"
    local rocket_file_path="/etc/supervisor/conf.d/rocket_app.conf"
    
    if [ -f "$rocket_file_path" ]; then
        sudo supervisorctl stop rocketApp
        rm $rocket_file_path
        sudo service supervisor restart
    fi

    echo  "\n[inet_http_server]" >> "$s_file_path"
    echo  "port=*:9001" >> "$s_file_path"
    echo  "username=rocket" >> "$s_file_path"
    echo  "password=rocket_ssh" >> "$s_file_path"
    
    cat > $rocket_file_path << ENDOFFILE
[program:rocketApp]
command=/usr/bin/node /var/rocket-ssh/rocket-app.js
autostart=true
autorestart=true
startretries=3
user=root
ENDOFFILE

    sudo service supervisor restart
    
    APP_NAME="rocketApp"
    # Get the status of the application
    status=$(sudo supervisorctl status $APP_NAME | awk '{print $2}')
    
    case "$status" in
        RUNNING)
            echo "Application $APP_NAME is already running. Restarting..."
            sudo supervisorctl restart $APP_NAME
            ;;
        STOPPED)
            echo "Application $APP_NAME is stopped. Starting..."
            sudo supervisorctl start $APP_NAME
            ;;
        *)
            echo "Application $APP_NAME is in an unknown state ($status)."
            sudo supervisorctl start $APP_NAME
            ;;
    esac
}

setup_bbr(){
    
    wget -N --no-check-certificate https://raw.githubusercontent.com/farhad-apps/rc-files/main/bbr.sh && chmod +x bbr.sh && bash bbr.sh
}


complete_install(){
    
    local api_address="$api_url/confirm-installed?token=$api_token&setup=main"
    response=$(curl -s "$api_address")
    echo "Complete install"
}

config_needrestart
install_packages
configure_nginx
configure_rocket_app
sleep 3 &
wait
configure_supervisor
complete_install
