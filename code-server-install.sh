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

read -p "请输入你的想要使用的端口 :" port

read -p "请输入你要设置的code-server密码 :" passwd

read -p "请输入你的邮箱用来注册acme(必须) :" email

apt-get -y update
apt-get -y install wget curl cron nginx socat


#2. 获取证书
green "2. 获取证书"
#acme
curl https://get.acme.sh | sh
source ~/.bashrc
green "停止web服务"
sudo kill -s 9 $(lsof -i:80 -t)
green "注册acme for ${email}"
~/.acme.sh/acme.sh --register-account -m ${email}
rm -rf ~/.acme/${domain}
~/.acme.sh/acme.sh  --issue   --standalone --keylength ec-256 --server letsencrypt -d ${domain}
green "证书放在 ~/.acme.sh/${domain}"


green "install code-server"
cd /root/
wget https://github.com/cdr/code-server/releases/download/v3.11.1/code-server-3.11.1-linux-amd64.tar.gz
tar -xzf code-server-3.11.1-linux-amd64.tar.gz
rm -rf code-server-3.11.1-linux-amd64.tar.gz
rm -rf /usr/lib/code-server
mv code-server-3.11.1-linux-amd64 /usr/lib/code-server
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
ExecStart=/usr/bin/code-server --bind-addr 127.0.0.1:${port} --user-data-dir /var/lib/code-server --auth password
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

green "反向代理"
rm -rf /etc/nginx/sites-available/${domain}
        cat > /etc/nginx/sites-available/${domain} <<-EOF
server {

    server_name ${domain};

    location / {
      proxy_pass http://localhost:${port}/;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
    }

    listen [::]:443 ssl ipv6only=on; 
    listen 443 ssl; 
    ssl_certificate /root/.acme.sh/${domain}/fullchain.cer; 
    ssl_certificate_key /root/.acme.sh/${domain}/${domain}.key; 
}
server {
    if (\$host = ${domain}) {
        return 301 https://\$host\$request_uri;
    } 
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 404; 
}
EOF

rm -rf /etc/nginx/sites-enabled/${domain}
ln -s /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/${domain}
nginx -t
nginx -s reload
nginx -s stop

systemctl daemon-reload
systemctl restart nginx
systemctl restart code-server

green "请访问你的网站 https://${domain}"

green "密码为 ${passwd}"



