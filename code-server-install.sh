#!/bin/bash
function blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
function green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
function red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
function version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; 
}

read -p "确认安装 :" ack

read -p "请输入你的域名 :" domain

read -p "请输入你要设置的code-server密码 :" passwd

green "apt-get update"
apt update

green "install nginx"
apt -y install nginx

green "install code-server"
wget https://github.com/cdr/code-server/releases/download/v3.10.1/code-server-3.10.1-linux-amd64.tar.gz
tar -xzf code-server-3.10.1-linux-amd64.tar.gz
rm -rf /usr/lib/code-server
mv code-server-3.10.1-linux-amd64 /usr/lib/code-server
rm -rf /usr/bin/code-server
ln -s /usr/lib/code-server/code-server /usr/bin/code-server
rm -rf /var/lib/code-server
mkdir -p /var/lib/code-server
rm -rf  /lib/systemd/system/code-server.service
green "configure code-server"
        cat > /lib/systemd/system/code-server.service <<-EOF
[Unit]
Description=code-server
After=nginx.service

[Service]
Type=simple
Environment=PASSWORD=${passwd}
ExecStart=/usr/bin/code-server --bind-addr 127.0.0.1:8080 --user-data-dir /var/lib/code-server --auth password
Restart=always

[Install]
WantedBy=multi-user.target
EOF

green "反向代理"
rm -rf /etc/nginx/sites-available/code-server
        cat > /etc/nginx/sites-available/code-server <<-EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${domain};

    location / {
      proxy_pass http://localhost:8080/;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
    }
}
EOF

cd /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/code-server /etc/nginx/sites-enabled/code-server
nginx -t
nginx -s reload
nginx -s stop

green "secure your site"
apt install certbot python3-certbot-nginx
ufw allow https
ufw reload
certbot --nginx -d ${domain}
systemctl restart nginx

green "请访问你的网站 ${domain}"

green "密码为 ${passwd}"

