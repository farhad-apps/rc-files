#!/bin/bash

api_url="{openApiUrl}";
api_token="{openApiToken}";

server_ip=$(hostname -I | awk '{print $1}')

DATA=$(cat <<EOF
{
"username": "$username",
"user_ip": "$trusted_ip",
"pid": "$trusted_port",
"server_ip": "$server_ip",
"bytes_received": "$bytes_received",
"bytes_sent": "$bytes_sent",
"type": "$script_type"
}
EOF
    )

encodedData=$(echo -n "$DATA" | base64 -w 0)

if [ "$script_type" == "client-connect" ]; then
    apiAddUrl="${api_url}/ovpn/uconnect?token=${api_token}"
else
    apiAddUrl="${api_url}/ovpn/udisconnect?token=${api_token}"
fi

jsonData="{\"data\": \"$encodedData\"}"

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$jsonData" "$apiAddUrl")

if [ "$response" -eq  200 ]; then
    exit 0
else
    exit 1
fi
