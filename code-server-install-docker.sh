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

read -p "请输入你想要使用的映射端口(eg:4000):" port

read -p "请输入你要设置的trojan密码 :" passwd

read -p "请输入你的邮箱用来注册acme(必须) :" email












server {

    server_name code.cuimouren.cn;

    location / {
      proxy_pass http://localhost:8080/;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection upgrade;
      proxy_set_header Accept-Encoding gzip;
    }

    listen [::]:443 ssl ipv6only=on; # managed by Certbot
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/code.cuimouren.cn/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/code.cuimouren.cn/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = code.cuimouren.cn) {
        return 301 https://$host$request_uri;
    } # managed by Certbot
    listen 80;
    listen [::]:80;
    server_name code.cuimouren.cn;
    return 404; # managed by Certbot
}
