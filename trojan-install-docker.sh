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

read -p "确认安装(enter) :" ack

read -p "请输入你的域名 :" trojan_domain

read -p "请输入你想要使用的起始映射端口(eg:4000):" port

read -p "请输入你要设置的trojan密码 :" trojan_passwd

read -p "请输入你的邮箱用来注册acme(必须) :" trojan_email

#安装前准备
mkdir -p ~/trojan_docker
cd trojan_docker
apt-get -y update
apt-get -y install wget curl cron nginx git socat

#1. 在宿主机中安装docker
green "1. 在宿主机中安装docker"
apt -y remove docker docker-engine docker.io
apt -y install apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -y install docker-ce docker-ce-cli containerd.io
green "docker安装成功"

#2. 在宿主机中获取证书
green "2. 在宿主机中获取证书"
#acme
curl https://get.acme.sh | sh
source ~/.bashrc
green "停止web服务"
kill -s 9 $(lsof -i:80 -t)
green "注册acme for ${trojan_email}"
~/.acme.sh/acme.sh --register-account -m ${trojan_email}
rm -rf ~/.acme/${trojan_domain}
~/.acme.sh/acme.sh  --issue   --standalone --keylength ec-256 --server letsencrypt -d ${trojan_domain}
green "安装证书 for ${trojan_domain}"
rm -rf ~/trojan_docker/trojancert/${trojan_domain}
mkdir -p ~/trojan_docker/trojancert/${trojan_domain}
cp ~/.acme.sh/${trojan_domain}_ecc/${trojan_domain}.key ~/trojan_docker/trojancert/${trojan_domain}/private.key
cp ~/.acme.sh/${trojan_domain}_ecc/fullchain.cer ~/trojan_docker/trojancert/${trojan_domain}/fullchain.cer
# ~/.acme.sh/acme.sh  --installcert  -d  ${trojan_domain}   \
#     --key-file   ~/trojan_docker/trojancert/${trojan_domain}/private.key \
#     --fullchain-file  ~/trojan_docker/trojancert/${trojan_domain}/fullchain.cer 
#证书放在 ~/trojan_docker/trojancert/${trojan_domain} 中
green "证书放在 ~/trojan_docker/trojancert/${trojan_domain}"
#3. 在宿主机中获取伪装网页
green "3. 在宿主机中获取伪装网页"
cd ~/trojan_docker
git clone https://github.com/cuiwenyao/cuiwenyao.io.git
#4. 在宿主机中配置好宿主机的nginx反向代理，$port
green "4. 在宿主机中配置好宿主机的nginx反向代理，$port"
rm /etc/nginx/sites-available/${trojan_domain}
rm /etc/nginx/sites-enabled/${trojan_domain}
        cat > /etc/nginx/sites-available/${trojan_domain} <<-EOF
server {
    server_name ${trojan_domain};

    location / {
      proxy_pass http://localhost:${port}/;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
    }

    listen [::]:443;
    listen 443 ssl; 
    ssl_certificate /root/.acme.sh/${trojan_domain}/fullchain.cer; 
    ssl_certificate_key /root/.acme.sh/${trojan_domain}/${trojan_domain}.key; 
}
server {
    if (\$host = ${trojan_domain}) {
        return 301 https://\$host\$request_uri;
    } 
    listen 80;
    listen [::]:80;
    server_name ${trojan_domain};
    return 404; 
}
EOF
cd /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/${trojan_domain}
ln -s /etc/nginx/sites-available/${trojan_domain} /etc/nginx/sites-enabled/${trojan_domain}
#5. 在宿主机中配置好构建镜像中nginx和trojan需要的配置文件
green "5. 在宿主机中配置好构建镜像中nginx和trojan需要的配置文件"
#nginx
        cat > ~/trojan_docker/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log  /var/log/nginx/access.log;
    sendfile        on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    server {
        listen       80;
        server_name  ${trojan_domain};
        root /etc/nginx/html;
        index index.php index.html index.htm;
    }
}
EOF
#trojan
    cat > ~/trojan_docker/config.json <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$trojan_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/etc/trojan/trojancert/${trojan_domain}/fullchain.cer",
        "key": "/etc/trojan/trojancert/${trojan_domain}/private.key",
        "key_password": "",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1"
        ],
        "alpn_port_override": {
            "h2": 81
        },
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "prefer_ipv4": false,
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": "",
        "key": "",
        "cert": "",
        "ca": ""
    }
}
EOF
cd ~
tar -cvf trojan_docker.tar ./trojan_docker/

#4. 构建docker镜像(编写Dockerfile)
green "4. 构建docker镜像(编写Dockerfile)"
green "1. 将**证书**和，**伪装网页**和构建镜像中nginx和trojan需要的**配置文件**COPY到镜像中。"
green "2. 在docker镜像中安装nginx和trojan。"
green "3. 将docker镜像中的**证书**和，**伪装网页**和构建镜像中nginx和trojan需要的**配置文件**放在合适的地方。"
green "4. 启动nginx和trojan"

cat > ~/trojan_docker/Dockerfile  <<-EOF
FROM ubuntu:20.04
COPY ./trojan_docker.tar /root/
EXPOSE ${port}
RUN apt -y update \
&& apt -y install nginx trojan \
&& cd ~         \
&& tar -xvf trojan_docker.tar \
&& mkdir -p /etc/trojan/trojancert/${trojan_domain}/ \
&& mv  ~/trojan_docker/trojancert/${trojan_domain}/private.key  /etc/trojan/trojancert/${trojan_domain}/private.key  \
&& mv  ~/trojan_docker/trojancert/${trojan_domain}/fullchain.cer   /etc/trojan/trojancert/${trojan_domain}/fullchain.cer   \
&& rm /etc/nginx/nginx.conf \
&& mv ~/trojan_docker/nginx.conf  /etc/nginx/nginx.conf \
&& rm /etc/trojan/config.json \
&& mv ~/trojan_docker/config.json  /etc/trojan/config.json \
&& rm -rf /etc/nginx/html \
&& mv ~/trojan_docker/cuiwenyao.io  /etc/nginx/html  \
&& rm -rf ~/trojan_docker/cuiwneyao.io 
CMD ["sh","-c","nginx && trojan"]
EOF

#5. 构建一个镜像
green "5. 构建一个镜像"
cd ~
docker image rm -f trojan_image
docker build -f ~/trojan_docker/Dockerfile -t trojan_image .

#6. 从构建完成的镜像启动一个容器，并指定端口 $port
docker container rm -f trojan_docker
port_end=$port+9
i=$port
while(( $i <= $port_end))
do
docker run  -itd -p $i:443 --name trojan${i} --restart=always  trojan_image
let i++
done 
systemctl restart nginx

#7. 保存镜像
green "保存镜像至 ~/trojan_image.tar.gz"
docker save trojan_image | gzip > trojan_image.tar.gz

#清理 
green "clean-----------------------------------------"
#rm -rf trojan_docker  trojan_docker.tar

green "trojan_docker安装成功"
green "config_client.json中为Linux下的proxy客户端配置示例"
green "config_clash.yml中为clash下的proxy客户端配置示例"

#Linux client 
rm -rf config_client.json
cat > config_client.json <<-EOF
{
    "run_type": "client",
    "local_addr": "127.0.0.1",
    "local_port": 1080,
    "remote_addr": "$trojan_domain",
    "remote_port": 443,
    "password": [
        "$trojan_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "verify": true,
        "verify_hostname": true,
        "cert": "",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "sni": "",
        "alpn": [
            "h2",
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "curves": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    }
}
EOF

#clash 
rm -rf config_clash.yml
cat > config_clash.yml <<-EOF
proxies:
    - {type: trojan, name: '${trojan_domain}: expr ${port} + 0', server: '${trojan_domain}', port: expr ${port} + 0, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 1}', server: '${trojan_domain}', port: ${expr ${port} + 1}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 2}', server: '${trojan_domain}', port: ${expr ${port} + 2}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 3}', server: '${trojan_domain}', port: ${expr ${port} + 3}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 4}', server: '${trojan_domain}', port: ${expr ${port} + 4}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 5}', server: '${trojan_domain}', port: ${expr ${port} + 5}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 6}', server: '${trojan_domain}', port: ${expr ${port} + 6}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 7}', server: '${trojan_domain}', port: ${expr ${port} + 7}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 8}', server: '${trojan_domain}', port: ${expr ${port} + 8}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true
    - {type: trojan, name: '${trojan_domain}: ${expr ${port} + 9}', server: '${trojan_domain}', port: ${expr ${port} + 9}, password: 'Yaoyao1234', sni: angeles.cuimouren.cn} #, skip-cert-verify: true

proxy-groups:
    - {name: PROXY, type: select, 
    proxies: [
    ${trojan_domain}: ${expr ${port} + 0},
    ${trojan_domain}: ${expr ${port} + 1},
    ${trojan_domain}: ${expr ${port} + 2},
    ${trojan_domain}: ${expr ${port} + 3},
    ${trojan_domain}: ${expr ${port} + 4},
    ${trojan_domain}: ${expr ${port} + 5},
    ${trojan_domain}: ${expr ${port} + 6},
    ${trojan_domain}: ${expr ${port} + 7},
    ${trojan_domain}: ${expr ${port} + 8},
    ${trojan_domain}: ${expr ${port} + 9}], 
    url: 'http://www.gstatic.com/generate_204', interval: 300} 


# Source: https://github.com/Loyalsoldier/clash-rules
rules:
  - RULE-SET,applications,DIRECT
  - DOMAIN,clash.razord.top,DIRECT
  - DOMAIN,yacd.haishan.me,DIRECT
  - RULE-SET,private,DIRECT
  - RULE-SET,reject,REJECT
  - RULE-SET,icloud,DIRECT
  - RULE-SET,apple,DIRECT
  - RULE-SET,google,DIRECT
  - RULE-SET,proxy,PROXY
  - RULE-SET,direct,DIRECT
  - RULE-SET,lancidr,DIRECT
  - RULE-SET,cncidr,DIRECT
  - RULE-SET,telegramcidr,PROXY
  - GEOIP,,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY

rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: ./ruleset/reject.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: ./ruleset/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: ./ruleset/apple.yaml
    interval: 86400

  google:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt"
    path: ./ruleset/google.yaml
    interval: 86400

  proxy:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: ./ruleset/proxy.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: ./ruleset/direct.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: ./ruleset/private.yaml
    interval: 86400

  gfw:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: ./ruleset/gfw.yaml
    interval: 86400

  greatfire:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/greatfire.txt"
    path: ./ruleset/greatfire.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: ./ruleset/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: ./ruleset/applications.yaml
    interval: 86400

EOF