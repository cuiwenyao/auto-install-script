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



