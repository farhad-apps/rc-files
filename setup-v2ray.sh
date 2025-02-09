#!/bin/bash

api_token="{apiToken}"
api_url="{apiUrl}"
vless_tcp_port={vlessTcpPort}
vmess_tcp_port={vmessTcpPort}
enable_http=1

xray_path="/var/rocket-ssh/xray"
xray_conf_path="/var/rocket-ssh/xray/conf/"
configs_file_path="/var/rocket-ssh/configs.json"

if [ -d $xray_path ]; then
    systemctl stop rsxray
    rm -R $xray_path
fi

mkdir -p $xray_path

file_exists() {
    if [[ ! -f "$1" ]]; then
        echo "config file does not exist."
        exit 1
    fi
}

trim_string() {
    echo "$1" | xargs
}

get_configs() {
    local path="$1"
    # Check if the config file exists
    file_exists "$configs_file_path"

    # Construct jq query and execute
    local jq_query=".${path}"
    local result=$(jq --raw-output "$jq_query // empty" "$configs_file_path")

    # If the result is empty, return null
    if [[ -z "$result" ]]; then
        echo "null"
    else
        # Trim the result and return
        trimmed_result=$(trim_string "$result")
        echo "$trimmed_result"
    fi
}

get_cpu_vendor(){
  case "$(uname -m)" in
    'i386' | 'i686')
      MACHINE='32'
      ;;
    'amd64' | 'x86_64')
      MACHINE='64'
      ;;
    'armv5tel')
      MACHINE='arm32-v5'
      ;;
    'armv6l')
      MACHINE='arm32-v6'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
      ;;
    'armv7' | 'armv7l')
      MACHINE='arm32-v7a'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
      ;;
    'armv8' | 'aarch64')
      MACHINE='arm64-v8a'
      ;;
    'mips')
      MACHINE='mips32'
      ;;
    'mipsle')
      MACHINE='mips32le'
      ;;
    'mips64')
      MACHINE='mips64'
      lscpu | grep -q "Little Endian" && MACHINE='mips64le'
      ;;
    'mips64le')
      MACHINE='mips64le'
      ;;
    'ppc64')
      MACHINE='ppc64'
      ;;
    'ppc64le')
      MACHINE='ppc64le'
      ;;
    'riscv64')
      MACHINE='riscv64'
      ;;
    's390x')
      MACHINE='s390x'
      ;;
    *)
      echo "error: The architecture is not supported."
      exit 1
      ;;
  esac

  echo $MACHINE
}

install_xray(){
  local arch=$(get_cpu_vendor)

  local url=$(wget -q -O- https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq --arg v "Xray-linux-$arch.zip" -r '.assets[] | select(.name == $v) | .browser_download_url')
  echo $url
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
    
  mkdir -p $xray_conf_path  
  
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
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
        $(if [ "$enable_http" -eq 1 ] || [ -z "$enable_http" ]; then echo ', "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "request": {
              "headers": {},
              "method": "GET",
              "path": ["/"],
              "version": "1.1"
            },
            "response": {
              "headers": {},
              "reason": "OK",
              "status": "200",
              "version": "1.1"
            },
            "type": "http"
          }
        }'; fi)
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
        $(if [ "$enable_http" -eq 1 ] || [ -z "$enable_http" ]; then echo ', "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "request": {
              "headers": {},
              "method": "GET",
              "path": ["/"],
              "version": "1.1"
            },
            "response": {
              "headers": {},
              "reason": "OK",
              "status": "200",
              "version": "1.1"
            },
            "type": "http"
          }
        }'; fi)
      }
    }
  ]
}
EOF

cat <<EOF >${xray_conf_path}y_deco_api.json
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api",
      "port": 65432
    }
  ]
}
EOF

cat <<EOF >${xray_conf_path}z_configs.json
{
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ],
  "stats": {},
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
  },
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      }
    ],
    "domainStrategy": "AsIs"
  }
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

enable_http=$(get_configs "servers_v2ray.enable_http")
install_xray
xray_log
create_default_configs
install_xray_service
complete_install
