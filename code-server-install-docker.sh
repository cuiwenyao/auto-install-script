#!/bin/bash

#code-server自动安装 docker版

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

read -p "请输入你的域名 :" domain

read -p "请输入你想要使用的映射端口(eg:4100):" port

read -p "请输入你要设置的trojan密码 :" passwd

read -p "请输入你的邮箱用来注册acme(必须) :" email


#1. 卸载旧的docker并安装新的docker环境
#2. 在宿主机中获取证书并在安装到宿主机上
#3. 在宿主机中配置好到docker的反向代理 ${port}:8080
#4. 在宿主机中配置好相关文件以及下载code-server /root/.config/code-server/config.yaml
#5. 编写Dockerfile并构建镜像
#6. 运行

#安装前准备
mkdir -p ~/trojan_docker
cd trojan_docker
apt-get -y update
apt-get -y install wget curl cron nginx socat

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

#2. 在宿主机中获取证书并在安装到宿主机上
green "2. 获取证书"
#acme
curl https://get.acme.sh | sh
source ~/.bashrc
green "停止web服务"
systemctl stop trojan
systemctl stop nginx
systemctl stop apache
systemctl stop apache2
green "注册acme for ${email}"
~/.acme.sh/acme.sh --register-account -m ${email}
rm -rf ~/.acme/${domain}
~/.acme.sh/acme.sh  --issue --standalone -d ${domain}
green "证书放在 ~/.acme.sh/${domain}"

#3. 在宿主机中配置好到docker的反向代理 ${port}:8080
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

#4. 在宿主机中配置好相关配置文件 /root/.config/code-server/config.yaml
rm -rf /root/code-server-install
mkdir -p /root/code-server-install
cd /root/code-server-install
wget https://github.com/cdr/code-server/releases/download/v3.11.1/code-server-3.11.1-linux-amd64.tar.gz
tar -xzf code-server-3.11.1-linux-amd64.tar.gz
mv code-server-3.11.1-linux-amd64 code-server
tar -cf code-server.tar code-server
gzip code-server.tar

cat > /root/code-server-install/code-server-config.yaml <<-EOF
bind-addr: 127.0.0.1:8080
auth: password
password: ${passwd}
cert: false
EOF

#5. 编写Dockerfile并构建镜像

cat > /root/code-server-install/Dockerfile  <<-EOF
FROM ubuntu:20.04
COPY ./code-server-config.yaml /root/
COPY ./code-server.tar.gz /root/
EXPOSE ${port}
RUN cd /root/ \
tar -xzf code-server.tar.gz \
rm code-server.tar.gz \ 
rm -rf /root/.config/code-server/config.yaml \
mv code-server-config.yaml /root/.config/code-server/config.yaml 

#CMD ["sh","-c","/root/code-server/code-server"]
EOF

#5. 构建一个镜像
green "5. 构建一个镜像"
cd /root/code-server-install
docker image rm -f code-server-image
docker build -f ~/code-server-install/Dockerfile -t code-server-image .


#6. 运行
systemctl restart nginx
docker container rm -f code-server-docker
docker run --name code-server-docker -itd -p ${port}:8080  code-server-image

#7. 保存镜像
green "保存镜像至 ~/code-server-image.tar.gz"
docker save code-server-image | gzip > code-server-image.tar.gz

#清理 
green "clean-----------------------------------------"
rm -rf ~/code-server-install
green "访问你的网站：https://${domain}"
green "密码：${passwd} "