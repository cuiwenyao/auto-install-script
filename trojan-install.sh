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

read -p "请输入你的域名 :" trojan_domain

read -p "请输入你要设置的trojan密码 :" trojan_passwd

read -p "请输入你的邮箱用来注册acme(必须) :" trojan_email

green "apt-get update"
apt update

green "安装trojan"
# 安装trojan 要求 Ubuntu 20.04 以上
apt -y install trojan
#安装nginx
apt -y install nginx
#安装git
apt -y install git
#安装letsencrypt
green "安装letsencrypt"
apt -y install letsencrypt
#安装 socat for acme
apt -y install socat
#acme
curl https://get.acme.sh | sh
source ~/.bashrc


#获取证书
#停止web服务
green "停止web服务"
sudo kill -s 9 $(lsof -i:80 -t)

#写入nginx配置
green "正在写入nginx配置文件 /etc/nginx/nginx.conf"
rm /etc/nginx/nginx.conf
        cat > /etc/nginx/nginx.conf <<-EOF
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


# 写入配置文件
rm /etc/trojan/config.json
    cat > /etc/trojan/config.json <<-EOF
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

rm /lib/systemd/system/trojan.service
    cat > /lib/systemd/system/trojan.service <<-EOF
[Unit]
Description=trojan
Documentation=man:trojan(1) https://trojan-gfw.github.io/trojan/config https://trojan-gfw.github.io/trojan/
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/trojan /etc/trojan/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

green "正在设置伪装站点，这里用的是我的博客"
rm -rf /etc/nginx/html
mkdir /etc/nginx/html
rm -rf cuiwneyao.io
git clone https://github.com/cuiwenyao/cuiwenyao.io.git
mv cuiwenyao.io/* /etc/nginx/html/
rm -rf cuiwneyao.io
green "设置伪装站点成功"

green "注册acme for ${trojan_email}"

~/.acme.sh/acme.sh --register-account -m ${trojan_email}
systemctl stop nginx
systemctl stop trojan
rm -rf ~/.acme/${trojan_domain}
~/.acme.sh/acme.sh  --issue --standalone -d ${trojan_domain}

green "安装证书 for ${trojan_domain}"
rm -rf /etc/trojan/trojancert/${trojan_domain}/
mkdir -p /etc/trojan/trojancert/${trojan_domain}/
~/.acme.sh/acme.sh  --installcert  -d  ${trojan_domain}   \
    --key-file   /etc/trojan/trojancert/${trojan_domain}/private.key \
    --fullchain-file  /etc/trojan/trojancert/${trojan_domain}/fullchain.cer \
    --reloadcmd  "systemctl restart trojan"	



green "nginx设为自启动"
systemctl enable nginx

green "restart nginx"
systemctl restart nginx

green "trojan设为自启动"
systemctl enable trojan

green "restart trojan"
systemctl restart trojan

green "trojan安装成功"
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
port: 7890
socks-port: 7891
redir-port: 7892
allow-lan: false
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
proxies:
    - {type: trojan, name: 'trojan', server: '$trojan_domain', port: 443, password: '$trojan_passwd', sni: download.windowsupdate.com, skip-cert-verify: true}
proxy-groups:
    - {name: Proxy, type: select, proxies: [自动选择, 'American.trojan']}
    - {name: 自动选择, type: url-test, proxies: ['American.trojan'], url: 'http://www.gstatic.com/generate_204', interval: 300} 
rules:
    - 'DOMAIN-SUFFIX,mzstatic.com,DIRECT'
    - 'DOMAIN-SUFFIX,akadns.net,DIRECT'
    - 'DOMAIN-SUFFIX,aaplimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,cdn-apple.com,DIRECT'
    - 'DOMAIN-SUFFIX,apple.com,DIRECT'
    - 'DOMAIN-SUFFIX,icloud.com,DIRECT'
    - 'DOMAIN-SUFFIX,icloud-content.com,DIRECT'
    - 'DOMAIN-SUFFIX,zcool.com,DIRECT'
    - 'DOMAIN-SUFFIX,cn,DIRECT'
    - 'DOMAIN-KEYWORD,-cn,DIRECT'
    - 'DOMAIN-KEYWORD,baotian.me,DIRECT'
    - 'DOMAIN-KEYWORD,jovi.cc,DIRECT'
    - 'DOMAIN-SUFFIX,126.com,DIRECT'
    - 'DOMAIN-SUFFIX,126.net,DIRECT'
    - 'DOMAIN-SUFFIX,127.net,DIRECT'
    - 'DOMAIN-SUFFIX,163.com,DIRECT'
    - 'DOMAIN-SUFFIX,360buyimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,36kr.com,DIRECT'
    - 'DOMAIN-SUFFIX,acfun.tv,DIRECT'
    - 'DOMAIN-SUFFIX,air-matters.com,DIRECT'
    - 'DOMAIN-SUFFIX,aixifan.com,DIRECT'
    - 'DOMAIN-SUFFIX,akamaized.net,DIRECT'
    - 'DOMAIN-KEYWORD,alicdn,DIRECT'
    - 'DOMAIN-KEYWORD,alipay,DIRECT'
    - 'DOMAIN-KEYWORD,taobao,DIRECT'
    - 'DOMAIN-SUFFIX,amap.com,DIRECT'
    - 'DOMAIN-SUFFIX,autonavi.com,DIRECT'
    - 'DOMAIN-KEYWORD,baidu,DIRECT'
    - 'DOMAIN-SUFFIX,bdimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,bdstatic.com,DIRECT'
    - 'DOMAIN-SUFFIX,bilibili.com,DIRECT'
    - 'DOMAIN-SUFFIX,caiyunapp.com,DIRECT'
    - 'DOMAIN-SUFFIX,clouddn.com,DIRECT'
    - 'DOMAIN-SUFFIX,cnbeta.com,DIRECT'
    - 'DOMAIN-SUFFIX,cnbetacdn.com,DIRECT'
    - 'DOMAIN-SUFFIX,cootekservice.com,DIRECT'
    - 'DOMAIN-SUFFIX,csdn.net,DIRECT'
    - 'DOMAIN-SUFFIX,ctrip.com,DIRECT'
    - 'DOMAIN-SUFFIX,dgtle.com,DIRECT'
    - 'DOMAIN-SUFFIX,dianping.com,DIRECT'
    - 'DOMAIN-SUFFIX,douban.com,DIRECT'
    - 'DOMAIN-SUFFIX,doubanio.com,DIRECT'
    - 'DOMAIN-SUFFIX,duokan.com,DIRECT'
    - 'DOMAIN-SUFFIX,easou.com,DIRECT'
    - 'DOMAIN-SUFFIX,ele.me,DIRECT'
    - 'DOMAIN-SUFFIX,feng.com,DIRECT'
    - 'DOMAIN-SUFFIX,fir.im,DIRECT'
    - 'DOMAIN-SUFFIX,frdic.com,DIRECT'
    - 'DOMAIN-SUFFIX,g-cores.com,DIRECT'
    - 'DOMAIN-SUFFIX,godic.net,DIRECT'
    - 'DOMAIN-SUFFIX,gtimg.com,DIRECT'
    - 'DOMAIN,cdn.hockeyapp.net,DIRECT'
    - 'DOMAIN-SUFFIX,hongxiu.com,DIRECT'
    - 'DOMAIN-SUFFIX,hxcdn.net,DIRECT'
    - 'DOMAIN-SUFFIX,iciba.com,DIRECT'
    - 'DOMAIN-SUFFIX,ifeng.com,DIRECT'
    - 'DOMAIN-SUFFIX,ifengimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,ipip.net,DIRECT'
    - 'DOMAIN-SUFFIX,iqiyi.com,DIRECT'
    - 'DOMAIN-SUFFIX,jd.com,DIRECT'
    - 'DOMAIN-SUFFIX,jianshu.com,DIRECT'
    - 'DOMAIN-SUFFIX,knewone.com,DIRECT'
    - 'DOMAIN-SUFFIX,le.com,DIRECT'
    - 'DOMAIN-SUFFIX,lecloud.com,DIRECT'
    - 'DOMAIN-SUFFIX,lemicp.com,DIRECT'
    - 'DOMAIN-SUFFIX,luoo.net,DIRECT'
    - 'DOMAIN-SUFFIX,meituan.com,DIRECT'
    - 'DOMAIN-SUFFIX,meituan.net,DIRECT'
    - 'DOMAIN-SUFFIX,mi.com,DIRECT'
    - 'DOMAIN-SUFFIX,miaopai.com,DIRECT'
    - 'DOMAIN-SUFFIX,microsoft.com,DIRECT'
    - 'DOMAIN-SUFFIX,microsoftonline.com,DIRECT'
    - 'DOMAIN-SUFFIX,miui.com,DIRECT'
    - 'DOMAIN-SUFFIX,miwifi.com,DIRECT'
    - 'DOMAIN-SUFFIX,mob.com,DIRECT'
    - 'DOMAIN-SUFFIX,netease.com,DIRECT'
    - 'DOMAIN-KEYWORD,officecdn,DIRECT'
    - 'DOMAIN-SUFFIX,oschina.net,DIRECT'
    - 'DOMAIN-SUFFIX,ppsimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,pstatp.com,DIRECT'
    - 'DOMAIN-SUFFIX,qcloud.com,DIRECT'
    - 'DOMAIN-SUFFIX,qdaily.com,DIRECT'
    - 'DOMAIN-SUFFIX,qdmm.com,DIRECT'
    - 'DOMAIN-SUFFIX,qhimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,qidian.com,DIRECT'
    - 'DOMAIN-SUFFIX,qihucdn.com,DIRECT'
    - 'DOMAIN-SUFFIX,qiniu.com,DIRECT'
    - 'DOMAIN-SUFFIX,qiniucdn.com,DIRECT'
    - 'DOMAIN-SUFFIX,qiyipic.com,DIRECT'
    - 'DOMAIN-SUFFIX,qq.com,DIRECT'
    - 'DOMAIN-SUFFIX,qqurl.com,DIRECT'
    - 'DOMAIN-SUFFIX,rarbg.to,DIRECT'
    - 'DOMAIN-SUFFIX,rr.tv,DIRECT'
    - 'DOMAIN-SUFFIX,ruguoapp.com,DIRECT'
    - 'DOMAIN-SUFFIX,segmentfault.com,DIRECT'
    - 'DOMAIN-SUFFIX,sinaapp.com,DIRECT'
    - 'DOMAIN-SUFFIX,sogou.com,DIRECT'
    - 'DOMAIN-SUFFIX,sogoucdn.com,DIRECT'
    - 'DOMAIN-SUFFIX,sohu.com,DIRECT'
    - 'DOMAIN-SUFFIX,soku.com,DIRECT'
    - 'DOMAIN-SUFFIX,speedtest.net,DIRECT'
    - 'DOMAIN-SUFFIX,sspai.com,DIRECT'
    - 'DOMAIN-SUFFIX,suning.com,DIRECT'
    - 'DOMAIN-SUFFIX,taobao.com,DIRECT'
    - 'DOMAIN-SUFFIX,tenpay.com,DIRECT'
    - 'DOMAIN-SUFFIX,tmall.com,DIRECT'
    - 'DOMAIN-SUFFIX,tudou.com,DIRECT'
    - 'DOMAIN-SUFFIX,umetrip.com,DIRECT'
    - 'DOMAIN-SUFFIX,upaiyun.com,DIRECT'
    - 'DOMAIN-SUFFIX,upyun.com,DIRECT'
    - 'DOMAIN-SUFFIX,v2ex.com,DIRECT'
    - 'DOMAIN-SUFFIX,veryzhun.com,DIRECT'
    - 'DOMAIN-SUFFIX,weather.com,DIRECT'
    - 'DOMAIN-SUFFIX,weibo.com,DIRECT'
    - 'DOMAIN-SUFFIX,xiami.com,DIRECT'
    - 'DOMAIN-SUFFIX,xiami.net,DIRECT'
    - 'DOMAIN-SUFFIX,xiaomicp.com,DIRECT'
    - 'DOMAIN-SUFFIX,ximalaya.com,DIRECT'
    - 'DOMAIN-SUFFIX,xmcdn.com,DIRECT'
    - 'DOMAIN-SUFFIX,xunlei.com,DIRECT'
    - 'DOMAIN-SUFFIX,yhd.com,DIRECT'
    - 'DOMAIN-SUFFIX,yihaodianimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,yinxiang.com,DIRECT'
    - 'DOMAIN-SUFFIX,ykimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,youdao.com,DIRECT'
    - 'DOMAIN-SUFFIX,youku.com,DIRECT'
    - 'DOMAIN-SUFFIX,zealer.com,DIRECT'
    - 'DOMAIN-SUFFIX,zhihu.com,DIRECT'
    - 'DOMAIN-SUFFIX,zhimg.com,DIRECT'
    - 'DOMAIN-SUFFIX,umeng.com,DIRECT'
    - 'DOMAIN-SUFFIX,local,DIRECT'
    - 'IP-CIDR,127.0.0.0/8,DIRECT'
    - 'IP-CIDR,172.16.0.0/12,DIRECT'
    - 'IP-CIDR,192.168.0.0/16,DIRECT'
    - 'IP-CIDR,192.168.3.0/16,DIRECT'
    - 'IP-CIDR,10.0.0.0/8,DIRECT'
    - 'IP-CIDR,17.0.0.0/8,DIRECT'
    - 'IP-CIDR,100.64.0.0/10,DIRECT'
    - 'GEOIP,CN,DIRECT'
    - 'DOMAIN,gs.apple.com,Proxy'
    - 'DOMAIN,itunes.apple.com,Proxy'
    - 'DOMAIN,beta.itunes.apple.com,Proxy'
    - 'DOMAIN,ai.google,Proxy'
    - 'DOMAIN-SUFFIX,amazonaws.com,Proxy'
    - 'DOMAIN-SUFFIX,awsstatic.com,Proxy'
    - 'DOMAIN-SUFFIX,awstrack.me,Proxy'
    - 'DOMAIN-SUFFIX,amazon.com,Proxy'
    - 'DOMAIN-SUFFIX,ant.design,Proxy'
    - 'DOMAIN-SUFFIX,applypixels.com,Proxy'
    - 'DOMAIN-SUFFIX,apple.com,Proxy'
    - 'DOMAIN-SUFFIX,azureedge.net,Proxy'
    - 'DOMAIN-SUFFIX,adobedtm.com,Proxy'
    - 'DOMAIN-SUFFIX,adobeccstatic.com,Proxy'
    - 'DOMAIN-SUFFIX,adobelogion.com,Proxy'
    - 'DOMAIN-SUFFIX,adobe.com,Proxy'
    - 'DOMAIN-SUFFIX,bechance.com,Proxy'
    - 'DOMAIN-SUFFIX,bechance.net,Proxy'
    - 'DOMAIN-SUFFIX,bestfolios.com,Proxy'
    - 'DOMAIN-SUFFIX,clippings.io,Proxy'
    - 'DOMAIN-SUFFIX,colourlovers.com,Proxy'
    - 'DOMAIN-SUFFIX,dribbble.com,Proxy'
    - 'DOMAIN-SUFFIX,dropbox.com,Proxy'
    - 'DOMAIN-SUFFIX,designernews.co,Proxy'
    - 'DOMAIN-SUFFIX,deviantart.com,Proxy'
    - 'DOMAIN-SUFFIX,deviantart.net,Proxy'
    - 'DOMAIN-SUFFIX,envato-static.com,Proxy'
    - 'DOMAIN-SUFFIX,envato.com,Proxy'
    - 'DOMAIN-SUFFIX,fontawesome.com,Proxy'
    - 'DOMAIN-SUFFIX,fancy.com,Proxy'
    - 'DOMAIN-SUFFIX,googleapis.com,Proxy'
    - 'DOMAIN-SUFFIX,github.com,Proxy'
    - 'DOMAIN-SUFFIX,github.io,Proxy'
    - 'DOMAIN-SUFFIX,goabstract.com,Proxy'
    - 'DOMAIN-SUFFIX,google.com,Proxy'
    - 'DOMAIN-SUFFIX,gmail.com,Proxy'
    - 'DOMAIN-SUFFIX,godaddy.com,Proxy'
    - 'DOMAIN-SUFFIX,hdwallpapers.in,Proxy'
    - 'DOMAIN-SUFFIX,iconfinder.com,Proxy'
    - 'DOMAIN-SUFFIX,imgur.com,Proxy'
    - 'DOMAIN-SUFFIX,instagram.com,Proxy'
    - 'DOMAIN-SUFFIX,imgix.net,Proxy'
    - 'DOMAIN-SUFFIX,kickstarter.com,Proxy'
    - 'DOMAIN-SUFFIX,live.com,Proxy'
    - 'DOMAIN-SUFFIX,lizhi.io,Proxy'
    - 'DOMAIN-SUFFIX,microsoft.com,Proxy'
    - 'DOMAIN-SUFFIX,medium.com,Proxy'
    - 'DOMAIN-SUFFIX,muz.li,Proxy'
    - 'DOMAIN-SUFFIX,mockupeditor.com,Proxy'
    - 'DOMAIN-SUFFIX,microsoft.com,Proxy'
    - 'DOMAIN-SUFFIX,nngroup.com,Proxy'
    - 'DOMAIN-SUFFIX,omnigroup.com,Proxy'
    - 'DOMAIN-SUFFIX,producthunt.com,Proxy'
    - 'DOMAIN-SUFFIX,pinterest.com,Proxy'
    - 'DOMAIN-SUFFIX,photolemur.com,Proxy'
    - 'DOMAIN-SUFFIX,reddit.com,Proxy'
    - 'DOMAIN-SUFFIX,segment.io,Proxy'
    - 'DOMAIN-SUFFIX,sfx.ms,Proxy'
    - 'DOMAIN-SUFFIX,setapp.com,Proxy'
    - 'DOMAIN-SUFFIX,sketchapp.com,Proxy'
    - 'DOMAIN-SUFFIX,sketch.cloud,Proxy'
    - 'DOMAIN-SUFFIX,stackoverflow.com,Proxy'
    - 'DOMAIN-SUFFIX,sketchpacks.com,Proxy'
    - 'DOMAIN-SUFFIX,smallpdf.com,Proxy'
    - 'DOMAIN-SUFFIX,techsmith.com,Proxy'
    - 'DOMAIN-SUFFIX,typora.io,Proxy'
    - 'DOMAIN-SUFFIX,themeforest.net,Proxy'
    - 'DOMAIN-SUFFIX,uistencils.com,Proxy'
    - 'DOMAIN-SUFFIX,ui8.net,Proxy'
    - 'DOMAIN-SUFFIX,unsplash.com,Proxy'
    - 'DOMAIN-SUFFIX,zeplin.io,Proxy'
    - 'DOMAIN-SUFFIX,pusher.com,Proxy'
    - 'DOMAIN-SUFFIX,mixpanel.com,Proxy'
    - 'DOMAIN-SUFFIX,gravatar.com,Proxy'
    - 'DOMAIN-SUFFIX,hockeyapp.net,Proxy'
    - 'DOMAIN-SUFFIX,cloudfront.net,Proxy'
    - 'DOMAIN-SUFFIX,gstatic.com,Proxy'
    - 'DOMAIN-SUFFIX,googleapis.com,Proxy'
    - 'DOMAIN-SUFFIX,goo.gl,Proxy'
    - 'DOMAIN-SUFFIX,material.io,Proxy'
    - 'DOMAIN-SUFFIX,googletagmanager.com,Proxy'
    - 'DOMAIN-SUFFIX,google-analytics.com,Proxy'
    - 'DOMAIN-SUFFIX,doubleclick.net,Proxy'
    - 'DOMAIN-SUFFIX,paddleapi.com,Proxy'
    - 'DOMAIN-SUFFIX,devmate.com,Proxy'
    - 'DOMAIN-KEYWORD,amazon,Proxy'
    - 'DOMAIN-KEYWORD,google,Proxy'
    - 'DOMAIN-KEYWORD,gmail,Proxy'
    - 'DOMAIN-KEYWORD,youtube,Proxy'
    - 'DOMAIN-KEYWORD,facebook,Proxy'
    - 'DOMAIN-SUFFIX,fb.me,Proxy'
    - 'DOMAIN-SUFFIX,fbcdn.net,Proxy'
    - 'DOMAIN-KEYWORD,twitter,Proxy'
    - 'DOMAIN-KEYWORD,instagram,Proxy'
    - 'DOMAIN-KEYWORD,dropbox,Proxy'
    - 'DOMAIN-SUFFIX,twimg.com,Proxy'
    - 'DOMAIN-KEYWORD,blogspot,Proxy'
    - 'DOMAIN-SUFFIX,youtu.be,Proxy'
    - 'DOMAIN-KEYWORD,whatsapp,Proxy'
    - 'DOMAIN-KEYWORD,admarvel,REJECT'
    - 'DOMAIN-KEYWORD,admaster,REJECT'
    - 'DOMAIN-KEYWORD,adsage,REJECT'
    - 'DOMAIN-KEYWORD,adsmogo,REJECT'
    - 'DOMAIN-KEYWORD,adsrvmedia,REJECT'
    - 'DOMAIN-KEYWORD,adwords,REJECT'
    - 'DOMAIN-KEYWORD,adservice,REJECT'
    - 'DOMAIN-KEYWORD,domob,REJECT'
    - 'DOMAIN-KEYWORD,duomeng,REJECT'
    - 'DOMAIN-KEYWORD,dwtrack,REJECT'
    - 'DOMAIN-KEYWORD,guanggao,REJECT'
    - 'DOMAIN-KEYWORD,lianmeng,REJECT'
    - 'DOMAIN-KEYWORD,omgmta,REJECT'
    - 'DOMAIN-KEYWORD,openx,REJECT'
    - 'DOMAIN-KEYWORD,partnerad,REJECT'
    - 'DOMAIN-KEYWORD,pingfore,REJECT'
    - 'DOMAIN-KEYWORD,supersonicads,REJECT'
    - 'DOMAIN-KEYWORD,tracking,REJECT'
    - 'DOMAIN-KEYWORD,uedas,REJECT'
    - 'DOMAIN-KEYWORD,umeng,REJECT'
    - 'DOMAIN-KEYWORD,usage,REJECT'
    - 'DOMAIN-KEYWORD,wlmonitor,REJECT'
    - 'DOMAIN-KEYWORD,zjtoolbar,REJECT'
    - 'DOMAIN-SUFFIX,club,REJECT'
    - 'DOMAIN-SUFFIX,9to5mac.com,Proxy'
    - 'DOMAIN-SUFFIX,abpchina.org,Proxy'
    - 'DOMAIN-SUFFIX,adblockplus.org,Proxy'
    - 'DOMAIN-SUFFIX,adobe.com,Proxy'
    - 'DOMAIN-SUFFIX,alfredapp.com,Proxy'
    - 'DOMAIN-SUFFIX,amplitude.com,Proxy'
    - 'DOMAIN-SUFFIX,ampproject.org,Proxy'
    - 'DOMAIN-SUFFIX,android.com,Proxy'
    - 'DOMAIN-SUFFIX,angularjs.org,Proxy'
    - 'DOMAIN-SUFFIX,aolcdn.com,Proxy'
    - 'DOMAIN-SUFFIX,apkpure.com,Proxy'
    - 'DOMAIN-SUFFIX,appledaily.com,Proxy'
    - 'DOMAIN-SUFFIX,appshopper.com,Proxy'
    - 'DOMAIN-SUFFIX,appspot.com,Proxy'
    - 'DOMAIN-SUFFIX,arcgis.com,Proxy'
    - 'DOMAIN-SUFFIX,archive.org,Proxy'
    - 'DOMAIN-SUFFIX,armorgames.com,Proxy'
    - 'DOMAIN-SUFFIX,aspnetcdn.com,Proxy'
    - 'DOMAIN-SUFFIX,att.com,Proxy'
    - 'DOMAIN-SUFFIX,awsstatic.com,Proxy'
    - 'DOMAIN-SUFFIX,azureedge.net,Proxy'
    - 'DOMAIN-SUFFIX,azurewebsites.net,Proxy'
    - 'DOMAIN-SUFFIX,bing.com,Proxy'
    - 'DOMAIN-SUFFIX,bintray.com,Proxy'
    - 'DOMAIN-SUFFIX,bit.com,Proxy'
    - 'DOMAIN-SUFFIX,bit.ly,Proxy'
    - 'DOMAIN-SUFFIX,bitbucket.org,Proxy'
    - 'DOMAIN-SUFFIX,bjango.com,Proxy'
    - 'DOMAIN-SUFFIX,bkrtx.com,Proxy'
    - 'DOMAIN-SUFFIX,blog.com,Proxy'
    - 'DOMAIN-SUFFIX,blogcdn.com,Proxy'
    - 'DOMAIN-SUFFIX,blogger.com,Proxy'
    - 'DOMAIN-SUFFIX,blogsmithmedia.com,Proxy'
    - 'DOMAIN-SUFFIX,blogspot.com,Proxy'
    - 'DOMAIN-SUFFIX,blogspot.hk,Proxy'
    - 'DOMAIN-SUFFIX,bloomberg.com,Proxy'
    - 'DOMAIN-SUFFIX,box.com,Proxy'
    - 'DOMAIN-SUFFIX,box.net,Proxy'
    - 'DOMAIN-SUFFIX,cachefly.net,Proxy'
    - 'DOMAIN-SUFFIX,chromium.org,Proxy'
    - 'DOMAIN-SUFFIX,cl.ly,Proxy'
    - 'DOMAIN-SUFFIX,cloudflare.com,Proxy'
    - 'DOMAIN-SUFFIX,cloudfront.net,Proxy'
    - 'DOMAIN-SUFFIX,cloudmagic.com,Proxy'
    - 'DOMAIN-SUFFIX,cmail19.com,Proxy'
    - 'DOMAIN-SUFFIX,cnet.com,Proxy'
    - 'DOMAIN-SUFFIX,cocoapods.org,Proxy'
    - 'DOMAIN-SUFFIX,comodoca.com,Proxy'
    - 'DOMAIN-SUFFIX,content.office.net,Proxy'
    - 'DOMAIN-SUFFIX,crashlytics.com,Proxy'
    - 'DOMAIN-SUFFIX,culturedcode.com,Proxy'
    - 'DOMAIN-SUFFIX,d.pr,Proxy'
    - 'DOMAIN-SUFFIX,danilo.to,Proxy'
    - 'DOMAIN-SUFFIX,dayone.me,Proxy'
    - 'DOMAIN-SUFFIX,db.tt,Proxy'
    - 'DOMAIN-SUFFIX,deskconnect.com,Proxy'
    - 'DOMAIN-SUFFIX,digicert.com,Proxy'
    - 'DOMAIN-SUFFIX,disq.us,Proxy'
    - 'DOMAIN-SUFFIX,disqus.com,Proxy'
    - 'DOMAIN-SUFFIX,disquscdn.com,Proxy'
    - 'DOMAIN-SUFFIX,dnsimple.com,Proxy'
    - 'DOMAIN-SUFFIX,docker.com,Proxy'
    - 'DOMAIN-SUFFIX,droplr.com,Proxy'
    - 'DOMAIN-SUFFIX,duckduckgo.com,Proxy'
    - 'DOMAIN-SUFFIX,dueapp.com,Proxy'
    - 'DOMAIN-SUFFIX,dytt8.net,Proxy'
    - 'DOMAIN-SUFFIX,edgecastcdn.net,Proxy'
    - 'DOMAIN-SUFFIX,edgekey.net,Proxy'
    - 'DOMAIN-SUFFIX,edgesuite.net,Proxy'
    - 'DOMAIN-SUFFIX,engadget.com,Proxy'
    - 'DOMAIN-SUFFIX,entrust.net,Proxy'
    - 'DOMAIN-SUFFIX,eurekavpt.com,Proxy'
    - 'DOMAIN-SUFFIX,evernote.com,Proxy'
    - 'DOMAIN-SUFFIX,fabric.io,Proxy'
    - 'DOMAIN-SUFFIX,fast.com,Proxy'
    - 'DOMAIN-SUFFIX,fastly.net,Proxy'
    - 'DOMAIN-SUFFIX,fc2.com,Proxy'
    - 'DOMAIN-SUFFIX,feedburner.com,Proxy'
    - 'DOMAIN-SUFFIX,feedly.com,Proxy'
    - 'DOMAIN-SUFFIX,feedsportal.com,Proxy'
    - 'DOMAIN-SUFFIX,fiftythree.com,Proxy'
    - 'DOMAIN-SUFFIX,firebaseio.com,Proxy'
    - 'DOMAIN-SUFFIX,flexibits.com,Proxy'
    - 'DOMAIN-SUFFIX,flickr.com,Proxy'
    - 'DOMAIN-SUFFIX,flipboard.com,Proxy'
    - 'DOMAIN-SUFFIX,g.co,Proxy'
    - 'DOMAIN-SUFFIX,gabia.net,Proxy'
    - 'DOMAIN-SUFFIX,geni.us,Proxy'
    - 'DOMAIN-SUFFIX,gfx.ms,Proxy'
    - 'DOMAIN-SUFFIX,ggpht.com,Proxy'
    - 'DOMAIN-SUFFIX,ghostnoteapp.com,Proxy'
    - 'DOMAIN-SUFFIX,git.io,Proxy'
    - 'DOMAIN-KEYWORD,github,Proxy'
    - 'DOMAIN-SUFFIX,globalsign.com,Proxy'
    - 'DOMAIN-SUFFIX,gmodules.com,Proxy'
    - 'DOMAIN-SUFFIX,godaddy.com,Proxy'
    - 'DOMAIN-SUFFIX,golang.org,Proxy'
    - 'DOMAIN-SUFFIX,gongm.in,Proxy'
    - 'DOMAIN-SUFFIX,goo.gl,Proxy'
    - 'DOMAIN-SUFFIX,goodreaders.com,Proxy'
    - 'DOMAIN-SUFFIX,goodreads.com,Proxy'
    - 'DOMAIN-SUFFIX,gravatar.com,Proxy'
    - 'DOMAIN-SUFFIX,gstatic.com,Proxy'
    - 'DOMAIN-SUFFIX,gvt0.com,Proxy'
    - 'DOMAIN-SUFFIX,hockeyapp.net,Proxy'
    - 'DOMAIN-SUFFIX,hotmail.com,Proxy'
    - 'DOMAIN-SUFFIX,icons8.com,Proxy'
    - 'DOMAIN-SUFFIX,ift.tt,Proxy'
    - 'DOMAIN-SUFFIX,ifttt.com,Proxy'
    - 'DOMAIN-SUFFIX,iherb.com,Proxy'
    - 'DOMAIN-SUFFIX,imageshack.us,Proxy'
    - 'DOMAIN-SUFFIX,img.ly,Proxy'
    - 'DOMAIN-SUFFIX,imgur.com,Proxy'
    - 'DOMAIN-SUFFIX,imore.com,Proxy'
    - 'DOMAIN-SUFFIX,instapaper.com,Proxy'
    - 'DOMAIN-SUFFIX,ipn.li,Proxy'
    - 'DOMAIN-SUFFIX,is.gd,Proxy'
    - 'DOMAIN-SUFFIX,issuu.com,Proxy'
    - 'DOMAIN-SUFFIX,itgonglun.com,Proxy'
    - 'DOMAIN-SUFFIX,itun.es,Proxy'
    - 'DOMAIN-SUFFIX,ixquick.com,Proxy'
    - 'DOMAIN-SUFFIX,j.mp,Proxy'
    - 'DOMAIN-SUFFIX,js.revsci.net,Proxy'
    - 'DOMAIN-SUFFIX,jshint.com,Proxy'
    - 'DOMAIN-SUFFIX,jtvnw.net,Proxy'
    - 'DOMAIN-SUFFIX,justgetflux.com,Proxy'
    - 'DOMAIN-SUFFIX,kat.cr,Proxy'
    - 'DOMAIN-SUFFIX,klip.me,Proxy'
    - 'DOMAIN-SUFFIX,libsyn.com,Proxy'
    - 'DOMAIN-SUFFIX,licdn.com,Proxy'
    - 'DOMAIN-SUFFIX,linkedin.com,Proxy'
    - 'DOMAIN-SUFFIX,linode.com,Proxy'
    - 'DOMAIN-SUFFIX,lithium.com,Proxy'
    - 'DOMAIN-SUFFIX,littlehj.com,Proxy'
    - 'DOMAIN-SUFFIX,live.com,Proxy'
    - 'DOMAIN-SUFFIX,live.net,Proxy'
    - 'DOMAIN-SUFFIX,livefilestore.com,Proxy'
    - 'DOMAIN-SUFFIX,llnwd.net,Proxy'
    - 'DOMAIN-SUFFIX,macid.co,Proxy'
    - 'DOMAIN-SUFFIX,macromedia.com,Proxy'
    - 'DOMAIN-SUFFIX,macrumors.com,Proxy'
    - 'DOMAIN-SUFFIX,mashable.com,Proxy'
    - 'DOMAIN-SUFFIX,mathjax.org,Proxy'
    - 'DOMAIN-SUFFIX,medium.com,Proxy'
    - 'DOMAIN-SUFFIX,mega.co.nz,Proxy'
    - 'DOMAIN-SUFFIX,mega.nz,Proxy'
    - 'DOMAIN-SUFFIX,megaupload.com,Proxy'
    - 'DOMAIN-SUFFIX,microsofttranslator.com,Proxy'
    - 'DOMAIN-SUFFIX,mindnode.com,Proxy'
    - 'DOMAIN-SUFFIX,mobile01.com,Proxy'
    - 'DOMAIN-SUFFIX,modmyi.com,Proxy'
    - 'DOMAIN-SUFFIX,msedge.net,Proxy'
    - 'DOMAIN-SUFFIX,myfontastic.com,Proxy'
    - 'DOMAIN-SUFFIX,name.com,Proxy'
    - 'DOMAIN-SUFFIX,nextmedia.com,Proxy'
    - 'DOMAIN-SUFFIX,nsstatic.net,Proxy'
    - 'DOMAIN-SUFFIX,nssurge.com,Proxy'
    - 'DOMAIN-SUFFIX,nyt.com,Proxy'
    - 'DOMAIN-SUFFIX,nytimes.com,Proxy'
    - 'DOMAIN-SUFFIX,office365.com,Proxy'
    - 'DOMAIN-SUFFIX,omnigroup.com,Proxy'
    - 'DOMAIN-SUFFIX,onedrive.com,Proxy'
    - 'DOMAIN-SUFFIX,onedrive.live.com,Proxy'
    - 'DOMAIN-SUFFIX,onenote.com,Proxy'
    - 'DOMAIN-SUFFIX,ooyala.com,Proxy'
    - 'DOMAIN-SUFFIX,openvpn.net,Proxy'
    - 'DOMAIN-SUFFIX,openwrt.org,Proxy'
    - 'DOMAIN-SUFFIX,orkut.com,Proxy'
    - 'DOMAIN-SUFFIX,osxdaily.com,Proxy'
    - 'DOMAIN-SUFFIX,outlook.com,Proxy'
    - 'DOMAIN-SUFFIX,ow.ly,Proxy'
    - 'DOMAIN-SUFFIX,paddleapi.com,Proxy'
    - 'DOMAIN-SUFFIX,parallels.com,Proxy'
    - 'DOMAIN-SUFFIX,parse.com,Proxy'
    - 'DOMAIN-SUFFIX,pdfexpert.com,Proxy'
    - 'DOMAIN-SUFFIX,periscope.tv,Proxy'
    - 'DOMAIN-SUFFIX,pinboard.in,Proxy'
    - 'DOMAIN-SUFFIX,pinterest.com,Proxy'
    - 'DOMAIN-SUFFIX,pixelmator.com,Proxy'
    - 'DOMAIN-SUFFIX,pixiv.net,Proxy'
    - 'DOMAIN-SUFFIX,playpcesor.com,Proxy'
    - 'DOMAIN-SUFFIX,playstation.com,Proxy'
    - 'DOMAIN-SUFFIX,playstation.com.hk,Proxy'
    - 'DOMAIN-SUFFIX,playstation.net,Proxy'
    - 'DOMAIN-SUFFIX,playstationnetwork.com,Proxy'
    - 'DOMAIN-SUFFIX,pushwoosh.com,Proxy'
    - 'DOMAIN-SUFFIX,rime.im,Proxy'
    - 'DOMAIN-SUFFIX,servebom.com,Proxy'
    - 'DOMAIN-SUFFIX,sfx.ms,Proxy'
    - 'DOMAIN-SUFFIX,shadowsocks.org,Proxy'
    - 'DOMAIN-SUFFIX,sharethis.com,Proxy'
    - 'DOMAIN-SUFFIX,shazam.com,Proxy'
    - 'DOMAIN-SUFFIX,skype.com,Proxy'
    - 'DOMAIN-SUFFIX,smartdnsProxy.com,Proxy'
    - 'DOMAIN-SUFFIX,smartmailcloud.com,Proxy'
    - 'DOMAIN-SUFFIX,sndcdn.com,Proxy'
    - 'DOMAIN-SUFFIX,sony.com,Proxy'
    - 'DOMAIN-SUFFIX,soundcloud.com,Proxy'
    - 'DOMAIN-SUFFIX,sourceforge.net,Proxy'
    - 'DOMAIN-SUFFIX,spotify.com,Proxy'
    - 'DOMAIN-SUFFIX,squarespace.com,Proxy'
    - 'DOMAIN-SUFFIX,sstatic.net,Proxy'
    - 'DOMAIN-SUFFIX,st.luluku.pw,Proxy'
    - 'DOMAIN-SUFFIX,stackoverflow.com,Proxy'
    - 'DOMAIN-SUFFIX,startpage.com,Proxy'
    - 'DOMAIN-SUFFIX,staticflickr.com,Proxy'
    - 'DOMAIN-SUFFIX,steamcommunity.com,Proxy'
    - 'DOMAIN-SUFFIX,symauth.com,Proxy'
    - 'DOMAIN-SUFFIX,symcb.com,Proxy'
    - 'DOMAIN-SUFFIX,symcd.com,Proxy'
    - 'DOMAIN-SUFFIX,tapbots.com,Proxy'
    - 'DOMAIN-SUFFIX,tapbots.net,Proxy'
    - 'DOMAIN-SUFFIX,tdesktop.com,Proxy'
    - 'DOMAIN-SUFFIX,techcrunch.com,Proxy'
    - 'DOMAIN-SUFFIX,techsmith.com,Proxy'
    - 'DOMAIN-SUFFIX,thepiratebay.org,Proxy'
    - 'DOMAIN-SUFFIX,theverge.com,Proxy'
    - 'DOMAIN-SUFFIX,time.com,Proxy'
    - 'DOMAIN-SUFFIX,timeinc.net,Proxy'
    - 'DOMAIN-SUFFIX,tiny.cc,Proxy'
    - 'DOMAIN-SUFFIX,tinypic.com,Proxy'
    - 'DOMAIN-SUFFIX,tmblr.co,Proxy'
    - 'DOMAIN-SUFFIX,todoist.com,Proxy'
    - 'DOMAIN-SUFFIX,trello.com,Proxy'
    - 'DOMAIN-SUFFIX,trustasiassl.com,Proxy'
    - 'DOMAIN-SUFFIX,tumblr.co,Proxy'
    - 'DOMAIN-SUFFIX,tumblr.com,Proxy'
    - 'DOMAIN-SUFFIX,tweetdeck.com,Proxy'
    - 'DOMAIN-SUFFIX,tweetmarker.net,Proxy'
    - 'DOMAIN-SUFFIX,twitch.tv,Proxy'
    - 'DOMAIN-SUFFIX,txmblr.com,Proxy'
    - 'DOMAIN-SUFFIX,typekit.net,Proxy'
    - 'DOMAIN-SUFFIX,ubertags.com,Proxy'
    - 'DOMAIN-SUFFIX,ublock.org,Proxy'
    - 'DOMAIN-SUFFIX,ubnt.com,Proxy'
    - 'DOMAIN-SUFFIX,ulyssesapp.com,Proxy'
    - 'DOMAIN-SUFFIX,urchin.com,Proxy'
    - 'DOMAIN-SUFFIX,usertrust.com,Proxy'
    - 'DOMAIN-SUFFIX,v.gd,Proxy'
    - 'DOMAIN-SUFFIX,vimeo.com,Proxy'
    - 'DOMAIN-SUFFIX,vimeocdn.com,Proxy'
    - 'DOMAIN-SUFFIX,vine.co,Proxy'
    - 'DOMAIN-SUFFIX,vivaldi.com,Proxy'
    - 'DOMAIN-SUFFIX,vox-cdn.com,Proxy'
    - 'DOMAIN-SUFFIX,vsco.co,Proxy'
    - 'DOMAIN-SUFFIX,vultr.com,Proxy'
    - 'DOMAIN-SUFFIX,w.org,Proxy'
    - 'DOMAIN-SUFFIX,w3schools.com,Proxy'
    - 'DOMAIN-SUFFIX,webtype.com,Proxy'
    - 'DOMAIN-SUFFIX,wikiwand.com,Proxy'
    - 'DOMAIN-SUFFIX,wikileaks.org,Proxy'
    - 'DOMAIN-SUFFIX,wikimedia.org,Proxy'
    - 'DOMAIN-SUFFIX,wikipedia.com,Proxy'
    - 'DOMAIN-SUFFIX,wikipedia.org,Proxy'
    - 'DOMAIN-SUFFIX,windows.com,Proxy'
    - 'DOMAIN-SUFFIX,windows.net,Proxy'
    - 'DOMAIN-SUFFIX,wire.com,Proxy'
    - 'DOMAIN-SUFFIX,wordpress.com,Proxy'
    - 'DOMAIN-SUFFIX,workflowy.com,Proxy'
    - 'DOMAIN-SUFFIX,wp.com,Proxy'
    - 'DOMAIN-SUFFIX,wsj.com,Proxy'
    - 'DOMAIN-SUFFIX,wsj.net,Proxy'
    - 'DOMAIN-SUFFIX,xda-developers.com,Proxy'
    - 'DOMAIN-SUFFIX,xeeno.com,Proxy'
    - 'DOMAIN-SUFFIX,xiti.com,Proxy'
    - 'DOMAIN-SUFFIX,yahoo.com,Proxy'
    - 'DOMAIN-SUFFIX,yimg.com,Proxy'
    - 'DOMAIN-SUFFIX,ying.com,Proxy'
    - 'DOMAIN-SUFFIX,yoyo.org,Proxy'
    - 'DOMAIN-SUFFIX,ytimg.com,Proxy'
    - 'DOMAIN-SUFFIX,telegra.ph,Proxy'
    - 'DOMAIN-SUFFIX,telegram.org,Proxy'
    - 'IP-CIDR,91.108.56.0/22,Proxy'
    - 'IP-CIDR,91.108.4.0/22,Proxy'
    - 'IP-CIDR,91.108.8.0/22,Proxy'
    - 'IP-CIDR,109.239.140.0/24,Proxy'
    - 'IP-CIDR,149.154.160.0/20,Proxy'
    - 'IP-CIDR,149.154.164.0/22,Proxy'
    - 'MATCH,Proxy'
EOF

