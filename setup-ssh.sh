#!/bin/bash

ssh_port={sshPort}
udp_port={udpPort}
api_token="{apiToken}"
api_url="{apiUrl}"

sudo apt-get install -y build-essential libpam0g-dev libcurl4-openssl-dev cmake libncurses5-dev libpcap-dev make

if ! getent group rocketSSH >/dev/null; then
  sudo groupadd rocketSSH
fi

# Function to install BadVPN using a script
setup_udpgw_service() {
   
    local username="videocall"

    if grep -q "^$username:" /etc/passwd; then
        echo "videocall is installed."
    else
        local vendorId=$(lscpu | awk -F': ' '/Vendor ID/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        if [ "$vendorId" = "ARM" ]; then
            sudo wget -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/rocket-ap/badvpn/master/udpgw-arm"
        else
            sudo wget -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/rocket-ap/badvpn/master/udpgw-x86"
        fi

        chmod 777 /usr/bin/badvpn-udpgw
        useradd -m videocall
    fi

    cat >  /etc/systemd/system/videocall.service << ENDOFFILE
[Unit]
Description=UDP forwarding for badvpn-tun2socks
After=nss-lookup.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:$udp_port --max-clients 999
User=videocall

[Install]
WantedBy=multi-user.target
ENDOFFILE

    sudo systemctl enable videocall
    sudo systemctl start videocall

    echo "videocall configured"
   
}

# Function to install Nethogs using a script
setup_nethogs() {
    sudo wget -O /root/nethogs.zip https://github.com/pro-apps-1/files/raw/main/my-neth.zip
    unzip /root/nethogs.zip -d /root
    mv -f /root/nethogs-json-master /root/nethogs
    cd /root/nethogs/
    chmod 744 /root/nethogs/determineVersion.sh
    sudo make install
    hash -r
    cp /usr/local/sbin/nethogs /usr/sbin/nethogs -f
    rm -fr /root/nethogs /root/nethogs.zip
    sudo setcap "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe" /usr/local/sbin/nethogs
}


build_pam_file(){

    mkdir /lib/security
    
    local file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/ssh/auth.c"
    # Define the name of the file you want to create
    local file_path="/lib/security/rocket_ssh_auth.c"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then

        sed -i "s|{api_token}|$api_token|g" "$file_path"
        sed -i "s|{api_url}|$api_url|g" "$file_path"

        # Compile the updated content (assuming it's a C file)
        compile_path="/lib/security/rocket_ssh_auth.so" 
        
        gcc -shared -o $compile_path -fPIC $file_path -lcurl -lpam -lpam_misc

        rm $file_path
    fi

}

# Function to configure PAM authentication
config_pam_auth() {
    
    local rocket_ssh_auth_file="/lib/security/rocket_ssh_auth.so"

    if [ -f "$rocket_ssh_auth_file" ]; then
  
        if ! sudo grep -q 'auth required rocket_ssh_auth.so$' /etc/pam.d/sshd; then
            echo "auth required rocket_ssh_auth.so" | sudo tee -a /etc/pam.d/sshd
        else
              echo "Not it auth required"
        fi
        
        if ! sudo grep -q 'session required rocket_ssh_auth.so$' /etc/pam.d/sshd; then
            echo "session required rocket_ssh_auth.so" | sudo tee -a /etc/pam.d/sshd
        fi
    fi

}


# Function to configure a ssh 
config_sshd() {
  
    local rocket_sshd_file="/etc/ssh/rocket_sshd_config"
    if [ -f "$rocket_sshd_file" ]; then
        rm $rocket_sshd_file
    fi
    
    touch $rocket_sshd_file

    if ! grep -q "Include /etc/ssh/rocket_sshd_config" /etc/ssh/sshd_config; then
        echo "Include /etc/ssh/rocket_sshd_config" | sudo tee -a /etc/ssh/sshd_config
    fi

    sudo sed -i '/^#\s*Port 22/s/^#//' /etc/ssh/sshd_config

    if ! grep -qE '^\s*ClientAliveInterval' $rocket_sshd_file; then
         echo "ClientAliveInterval 30" | sudo tee -a $rocket_sshd_file
    fi

    if ! grep -qE '^\s*ClientAliveCountMax' $rocket_sshd_file; then
        echo "ClientAliveCountMax 1" | sudo tee -a $rocket_sshd_file
    fi

    if ! grep -qE "^\s*Port $ssh_port" $rocket_sshd_file; then
        echo "Port $ssh_port" | sudo tee -a $rocket_sshd_file
    fi

    sudo systemctl restart ssh
    sudo systemctl restart sshd

    rm /tmp/rssh

}

complete_install(){

    local api_address="$api_url/confirm-installed?token=$api_token&setup=ssh"
    response=$(curl -s "$api_address")

    echo "installed_ssh"
}

# Call the functions to perform the tasks
setup_nethogs
setup_udpgw_service
build_pam_file
config_pam_auth
config_sshd
complete_install
