# auto install script 

这是一个自动配置各种应用的脚本合集。

## trojan-install
学习Linux的shell命令使用方法，顺便写一个Trojan自动配置的程序

本脚本只支持Ubuntu20.04及以上版本

请以root身份运行程序

```bash
wget https://raw.githubusercontent.com/cuiwenyao/auto-install-script/master/trojan-install.sh && chmod u+x trojan-install.sh && ./trojan-install.sh
```


linux 网络加速

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod u+x tcp.sh && ./tcp.sh
```

来源于
https://github.com/chiakge/Linux-NetSpeed

## trojan-install-docker

这是一个使用docker运行trojan的安装脚本。

```bash
wget https://raw.githubusercontent.com/cuiwenyao/auto-install-script/master/trojan-install-docker.sh && chmod u+x trojan-install-docker.sh && ./trojan-install-docker.sh
```

## code-server-install

自动安装code-server

```shell
wget https://raw.githubusercontent.com/cuiwenyao/auto-install-script/master/code-server-install.sh && chmod u+x code-server-install.sh && ./code-server-install.sh 
```