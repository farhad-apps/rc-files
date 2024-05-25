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

# Function to install required packages
install_packages() {
    sudo apt-get update -y
    
    # remove packages
    local remove_packages=("supervisor" "nginx")

    for rpackage in "${remove_packages[@]}"; do
        sudo apt-get purge -y "$rpackage"
    done

    # install packages
    local install_packages=("nginx" "nodejs" "supervisor" "psmisc" "unzip")

    for ipackage in "${install_packages[@]}"; do
        sudo apt-get install -y "$ipackage"
    done

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


complete_install(){
    local api_address="$api_url/confirm-installed?token=$api_token&setup=main"
    response=$(curl -s "$api_address")
}


# Call the functions to perform the tasks
config_needrestart
install_packages
#configure_nginx
#configure_rocket_app
#configure_supervisor
complete_install
