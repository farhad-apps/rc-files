#!/bin/bash

api_token="{apiToken}"
api_url="{apiUrl}"

# Function to check and update needrestart configuration

config_needrestart() {
    local nrconf_file="/etc/needrestart/needrestart.conf"

}

# Function to install required packages
install_packages() {
    sudo apt-get update -y
    # remove packages
    local remove_packages=("supervisor" "nginx")
}


configure_rocket_app(){

 
}


complete_install(){
    
}


# Call the functions to perform the tasks
config_needrestart
install_packages
#configure_nginx
#configure_rocket_app
#configure_supervisor
complete_install
