#!/bin/bash

ovpn_port={ovpnPort}
ovpn_domain="{ovpnDomain}"
api_token="{apiToken}"
api_url="{apiUrl}"

if [ -f "/etc/openvpn/server.conf" ]; then
    systemctl stop openvpn
    sudo apt-get purge -y openvpn
    rm -R /etc/openvpn
fi

install_dependencies(){

  apt-get install -y openvpn easy-rsa iptables ca-certificates tar gnupg
}

install_easyrsa(){

   mkdir /etc/openvpn/easy-rsa
   ln -s /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
   sudo chown root /etc/openvpn/easy-rsa
   chmod 700 /etc/openvpn/easy-rsa
   chown -R root:root /etc/openvpn/easy-rsa/
}

build_certificates(){
    cd /etc/openvpn/easy-rsa
    /etc/openvpn/easy-rsa/easyrsa --batch init-pki >/dev/null 2>&1
    /etc/openvpn/easy-rsa/easyrsa --batch build-ca nopass >/dev/null 2>&1
    /etc/openvpn/easy-rsa/easyrsa --batch --days=3650 build-server-full server nopass >/dev/null 2>&1
    /etc/openvpn/easy-rsa/easyrsa --batch --days=3650 build-client-full client nopass >/dev/null 2>&1
    openvpn --genkey --secret /etc/openvpn/tc.key >/dev/null 2>&1
    openssl dhparam -out /etc/openvpn/dh.pem 2048 >/dev/null 2>&1
    sleep 5 && echo "build_certificates"
    
    cp /etc/openvpn/easy-rsa/pki/{ca.crt,issued/server.crt,issued/client.crt,private/client.key,private/server.key} /etc/openvpn/
}

openvpn_auth_files(){

    touch /etc/openvpn/ulogin.sh
    touch /etc/openvpn/umanager.sh

    local ulogin_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/openvpn/ovpn-ulogin.sh"
    local ulogin_file_path="/etc/openvpn/ulogin.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$ulogin_file_path" "$ulogin_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{openApiToken}|$api_token|g" "$ulogin_file_path"
        sed -i "s|{openApiUrl}|$api_url|g" "$ulogin_file_path"
    fi

    local uman_file_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/openvpn/ovpn-umanager.sh"
    local uman_file_path="/etc/openvpn/umanager.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$uman_file_path" "$uman_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{openApiToken}|$api_token|g" "$uman_file_path"
        sed -i "s|{openApiUrl}|$api_url|g" "$uman_file_path"
    fi

    chmod +x /etc/openvpn/ulogin.sh
    chmod +x /etc/openvpn/umanager.sh

}

configure_server_conf(){
    mkdir /etc/openvpn/ccd

    local conf_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/openvpn/ovpn-server.conf"
    local conf_path="/etc/openvpn/server.conf"

    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$conf_path" "$conf_url"

    if [ $? -eq 0 ]; then

        sed -i "s|{openPort}|$ovpn_port|g" "$conf_path"
    fi
}

configure_client_conf(){
    
    local conf_url="https://raw.githubusercontent.com/farhad-apps/rc-files/main/openvpn/ovpn-client.conf"
    local conf_path="/etc/openvpn/myuser.txt"

    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$conf_path" "$conf_url"

    if [ $? -eq 0 ]; then

        sed -i "s|{openDomain}|$ovpn_domain|g" "$conf_path"
        sed -i "s|{openPort}|$ovpn_port|g" "$conf_path"

        ca_file="/etc/openvpn/ca.crt"
        tls_file="/etc/openvpn/tc.key"
        claint_cert_file="/etc/openvpn/client.crt"
        claint_key_file="/etc/openvpn/client.key"

        ca_content=$(<"$ca_file")
        claint_cert_content=$(awk '/BEGIN/,/END CERTIFICATE/' "$claint_cert_file")
        claint_key_content=$(<"$claint_key_file")
        tls_content=$(<"$tls_file")

cat <<EOF >> "$conf_path"

<ca>
$ca_content
</ca>
<cert>
$claint_cert_content
</cert>
<key>
$claint_key_content
</key>
<tls-crypt>
$tls_content
</tls-crypt>
EOF
    
    fi
}

configure_iptable(){

    # Get primary NIC device name
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    PROTOCOL="udp"
echo "#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $ovpn_port -j ACCEPT" >/etc/openvpn/add-iptables-rules.sh

# Script to remove rules
echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $ovpn_port -j ACCEPT" >/etc/openvpn/rm-iptables-rules.sh

echo "[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/openvpn/add-iptables-rules.sh
ExecStop=/etc/openvpn/rm-iptables-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-openvpn.service

    chmod +x /etc/openvpn/add-iptables-rules.sh
    chmod +x /etc/openvpn/rm-iptables-rules.sh

    systemctl daemon-reload
    systemctl enable iptables-openvpn
    systemctl start iptables-openvpn
}

configure_ip_forward(){

    # Make ip forwading and make it persistent
    echo 1 > "/proc/sys/net/ipv4/ip_forward"
    echo "net.ipv4.ip_forward = 1" >> "/etc/sysctl.conf"
}

start_openvpn(){

   systemctl daemon-reload
   systemctl enable openvpn
   systemctl start openvpn
   
   echo "OpenVPN Success Configuration"
}

complete_install(){

    local api_address="$api_url/confirm-installed?token=$api_token&setup=openvpn"
    response=$(curl -s "$api_address")
    echo "installed_openvpn"
}


install_dependencies
install_easyrsa
build_certificates
configure_server_conf
configure_client_conf
openvpn_auth_files
configure_iptable
configure_ip_forward
start_openvpn
complete_install
