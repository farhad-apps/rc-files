#!/bin/bash

api_url="{openApiUrl}";
api_token="{openApiToken}";

server_ip=$(hostname -I | awk '{print $1}')

DATA=$(cat <<EOF
{
"username": "$username",
"password": "$password"
}
EOF
  )

encodedData=$(echo -n "$DATA" | base64 -w 0)
apiAddUrl="${api_url}/ovpn/ulogin?token=${api_token}"

jsonData="{\"data\": \"$encodedData\"}"

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$jsonData" "$apiAddUrl")

if [ "$response" -eq  200 ]; then
    exit 0
else
    exit 1
fi
