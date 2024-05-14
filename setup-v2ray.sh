#!/bin/bash

api_token={apiToken}
api_url={apiUrl}
vless_tcp_port={vlessTcpPort}
vmess_tcp_port={vmessTcpPort}

xray_path="/var/rocket-ssh/xray"
xray_conf_path="/var/rocket-ssh/xray/conf/"
mkdir -p $xray_path

get_cpu_vendor(){
  local arch=$(uname -m)
  case $arch in
  "i386" | "i686") arch=1 ;;
  "x86_64") arch=2 ;;
  esac

  case $arch in
  1) arch="32" ;;
  2) arch="64" ;;
  3) arch="arm32-v5" ;;
  4) arch="arm32-v6" ;;
  5) arch="arm32-v7a" ;;
  6) arch="arm64-v8a" ;;
  *)
    echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid option"
    exit 1
    ;;
  esac

  echo $arch
}

install_xray(){
  local arch=$(get_cpu_vendor)

  local url=$(wget -q -O- https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq --arg v "Xray-linux-$arch.zip" -r '.assets[] | select(.name == $v) | .browser_download_url')
  
  wget -O "$xray_path/xray.zip" "$url"
  unzip "$xray_path/xray.zip" -d "$xray_path/"
  rm "$xray_path/xray.zip"
}

install_xray_service(){
  rm -rf /etc/systemd/system/rsxray.service
  touch /etc/systemd/system/rsxray.service

  execStart="$xray_path/xray run -confdir $xray_path/conf"
  
cat <<EOF >/etc/systemd/system/rsxray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable rsxray
  systemctl start rsxray
  systemctl status rsxray

}

create_default_configs(){

cat <<EOF >${xray_conf_path}00_log.json
{
  "log": {
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF


cat <<EOF >${xray_conf_path}01_vless_tcp.json
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${vless_tcp_port},
      "protocol": "vless",
      "tag": "VLESSTCP",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ]
}
EOF

cat <<EOF >${xray_conf_path}02_vmess_tcp.json
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${vmess_tcp_port},
      "protocol": "vmess",
      "tag": "VMESSTCP",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ]
}
EOF

cat <<EOF >${xray_conf_path}w_routing.json
{
  "routing": {
    "rules": [
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "domain": ["domain:gstatic.com", "domain:googleapis.com", "domain:googleapis.cn"],
        "type": "field",
        "outboundTag": "z_direct_outbound"
      }
    ],
    "domainStrategy": "AsIs",
  }
}
EOF

cat <<EOF >${xray_conf_path}x_dns.json
{ 
  "dns": {
    "servers": ["localhost"]
  }
}
EOF

cat <<EOF >${xray_conf_path}y_policy.json
{ 
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  }
}
EOF

cat <<EOF >${xray_conf_path}z_direct_outbound.json
{ 
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "tag": "z_direct_outbound"
    }
  ]
}
EOF

}

xray_log(){
  mkdir -p /var/log/v2ray
  touch /var/log/v2ray/error.log
  install -d -m 700 -o nobody -g nogroup /var/log/v2ray/
  install -m 600 -o nobody -g nogroup /dev/null /var/log/v2ray/error.log
}

complete_install(){
    local api_address="$api_url/confirm-installed?token=$api_token&setup=v2ray"
    response=$(curl -s "$api_address")
    echo "installed_v2ray"
}


install_xray
create_base_config
xray_log
install_xray_service
create_default_configs
complete_install
