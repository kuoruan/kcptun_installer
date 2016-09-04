#!/bin/bash

<<COM
Copyright (C) 2016 Xingwang Liao

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
COM

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

## 定义常量

SHELL_VERSION=9
CONFIG_VERSION=4
INIT_VERSION=2
KCPTUN_TAG_NAME=

CUR_DIR=`pwd` # 当前目录
KCPTUN_INSTALL_DIR="/usr/share/kcptun" # kcptun 默认安装目录
KCPTUN_LOG_FILE="/var/log/kcptun.log"
KCPTUN_RELEASES_URL="https://api.github.com/repos/xtaci/kcptun/releases"
KCPTUN_TAGS_URL="https://github.com/xtaci/kcptun/tags"
SHELL_VERSION_INFO_URL="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/kcptun.json"

## 默认参数
D_PORT=29900
D_TARGET_IP="127.0.0.1"
D_TARGET_PORT="12948"
D_CRYPT="aes"
D_MODE="fast"
D_MTU=1350
D_SNDWND=1024
D_RCVWND=1024
D_DATASHARD=10
D_PARITYSHARD=3
D_DSCP=0

## 退出代码

# 正常代码
SUCCESS=0 # 脚本正常退出

# 错误代码
ERROR=1 # 常规错误
E_INSTALLED_SUPERVISOR=65
E_INSTALL_DEPENDENCE=66 # 安装依耐环境失败
E_NOT_SUPPORT_OS=75 # 不支持的系统
E_NOT_SUPPORT_VERION=76 # 不支持的系统版本
E_CREATE_DIR=85 # 创建文件夹失败
E_CREATE_FILE=86 # 创建文件失败
E_NOTROOT=87 # 非root权限用户运行的错误码
E_XCD=88 # 切换目录失败
E_FILE_NOT_FOUND=89 # 文件未找到
E_NETWORK=100 # 网络错误
E_WRONG_TAG=101 # TAG未找到
E_DOWNLOAD_FAILED=102 # 下载失败

clear

echo
echo "#############################################################"
echo "# Kcptun 服务端一键安装脚本                                 #"
echo "# 该脚本支持 Kcptun 服务端的安装、更新、卸载及配置          #"
echo "# 官方网站: https://blog.kuoruan.com/                       #"
echo "# 脚本作者: Index <kuoruan@gmail.com>                       #"
echo "# 致谢: 脚本编写过程中参考了 @teddysun 的SS一键安装脚本     #"
echo "# QQ交流群: 43391448                                        #"
echo "#############################################################"

# 检查当前用户是否拥有管理员权限
function permission_check() {
    [ $EUID -ne 0 ] && {
        echo
        echo "权限错误, 请使用 root 用户运行此脚本!"
        exit_with_error $E_NOTROOT
    }
}

# 检查并获取系统信息
function linux_check() {
    if $(grep -qi "CentOS" /etc/issue) || $(grep -q "CentOS" /etc/*-release); then
        OS="CentOS"
    elif $(grep -qi "Ubuntu" /etc/issue) || $(grep -q "Ubuntu" /etc/*-release); then
        OS="Ubuntu"
    elif $(grep -qi "Debian" /etc/issue) || $(grep -q "Debian" /etc/*-release); then
        OS="Debian"
    else
        echo
        echo "本脚本仅支持 CentOS 6+, Debian 7+ 或者 Ubuntu 12+, 其他系统请向脚本作者反馈以寻求支持!"
        exit_with_error $E_NOT_SUPPORT_OS
    fi

    OS_VSRSION=$(grep -oEh "[0-9]+" /etc/*-release | head -n 1) || {
        echo
        echo "无法获取操作系统版本..."
        exit_with_error $E_NOT_SUPPORT_VERION
    }

    if [ "$OS" = "CentOS" -a $OS_VSRSION -lt 6 ]; then
        echo
        echo "暂不支持 CentOS 6 以下版本, 请升级系统或向脚本作者反馈以寻求支持!"
        exit_with_error $E_NOT_SUPPORT_VERION
    elif [ "$OS" = "Ubuntu" -a $OS_VSRSION -lt 12 ]; then
        echo
        echo "暂不支持 Ubuntu 12 以下版本, 请升级系统或向脚本作者反馈以寻求支持!"
        exit_with_error $E_NOT_SUPPORT_VERION
    elif [ "$OS" = "Debian" -a $OS_VSRSION -lt 7 ]; then
        echo
        echo "暂不支持 Debian 7 以下版本, 请升级系统或向脚本作者反馈以寻求支持!"
        exit_with_error $E_NOT_SUPPORT_VERION
    else
        echo
        echo "获取系统信息成功..."
    fi
}

# 获取系统位数
function get_arch() {
    if $(uname -m | grep -q "64") || $(getconf LONG_BIT | grep -q "64"); then
        ARCH=64
        SPRUCE_TYPE="linux-amd64"
        FILE_SUFFIX="linux_amd64"
    else
        ARCH=32
        SPRUCE_TYPE="linux-386"
        FILE_SUFFIX="linux_386"
    fi
}

# 获取服务器的IP地址
function get_server_ip() {
	SERVER_IP=$(ip addr | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | grep -Ev "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1) || \
    SERVER_IP=$(wget -q -O - ipv4.icanhazip.com)
}

# 禁用 selinux
function disable_selinux() {
    [ -s /etc/selinux/config ] && $(grep -q "SELINUX=enforcing" /etc/selinux/config) && {
        sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
        setenforce 0
    }
}

# 非正常退出
function exit_with_error() {
    local error_code=${1:-$ERROR}
    echo
    echo "Kcptun 服务端安装失败！"
    echo "希望你能记录下错误信息, 然后将错误信息发送给我"
    echo "我的邮箱: kuoruan@gmail.com"
    echo "反馈请加入QQ群: 43391448"
    echo "扩软博客：https://blog.kuoruan.com"
    echo
    exit $error_code
}

# 任意键继续
function any_key_to_continue() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

# 检查是否已经安装
function installed_check() {
    [ -s /etc/supervisord.conf ] && {
        echo
        echo "检测到你曾经通过其他方式安装过 Supervisor , 这会和本脚本安装的 Supervisor 产生冲突, 推荐你备份配置后卸载原有版本"
        echo "已安装的 Supervisor 配置文件路径为: /etc/supervisord.conf"
        echo "通过本脚本安装的 Supervisor 配置文件路径为: /etc/supervisor/supervisord.conf"
        echo -n "你可以通过 "
        [ "$OS" = "CentOS" ] && echo -n "yum remove supervisor" || echo -n "apt-get remove supervisor"
        echo " 来卸载原有版本"

        exit_with_error $E_INSTALLED_SUPERVISOR
    }

    [ -s /etc/supervisor/conf.d/kcptun.conf -a -d /usr/share/kcptun/ ] && {
        echo
        echo -n "检测到你已安装 Kcptun 服务端, "

        while :
        do
            echo "请选择你希望的操作:"
            echo "(1) 覆盖安装"
            echo "(2) 重新配置"
            echo "(3) 检查更新"
            echo "(4) 查看当前配置"
            echo "(5) 查看日志输出"
            echo "(6) 手动输入版本安装"
            echo "(7) 卸载"
            echo "(8) 退出"
            read -p "(请选择 [1~8], 默认: 1):" sel
            echo
            [ -z "$sel" ] && sel=1 || expr $sel + 0 &>/dev/null

            if [ $? -eq 0 ]; then
                case $sel in
                    1 )
                        echo "开始覆盖安装 Kcptun 服务端..."
                        return $SUCCESS;;
                    2 )
                        reconfig_kcptun
                        exit $SUCCESS;;
                    3 )
                        check_update
                        exit $SUCCESS;;
                    4 )
                        show_cur_config
                        exit $SUCCESS;;
                    5 )
                        tail -n 20 -f "$KCPTUN_LOG_FILE"
                        exit $SUCCESS;;
                    6 )
                        manual_install
                        exit $SUCCESS;;
                    7 )
                        uninstall_kcptun
                        exit $SUCCESS;;
                    8 )
                        exit $SUCCESS;;
                    * )
                        echo "请输入有效数字 1~8 !"
                        continue;;
                esac
            else
                echo "输入有误, 请输入数字!"
            fi
        done
    }
}

# 设置参数
function set_kcptun_config() {
    echo
    echo "开始配置参数..."
    # 设置 Kcptun 端口
    while :
    do
        echo
        echo -e "请输入 Kcptun 服务端运行端口 [1-65535]:"
        read -p "(默认: $D_PORT):" kcptun_port
        echo
        [ -z "$kcptun_port" ] && kcptun_port=$D_PORT || expr $kcptun_port + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            if [ $kcptun_port -ge 1 -a $kcptun_port -le 65535 ]; then

                $(netstat -an | grep -qE "[0-9:]:${kcptun_port} .+LISTEN") && {
                    echo "端口已被占用, 请重新输入!"
                } || {
                    echo "---------------------------"
                    echo "端口 = $kcptun_port"
                    echo "---------------------------"
                    break
                }

            else
                echo "输入有误, 请输入 1~65535 之间的数字!"
            fi
        else
            echo "输入有误, 请输入数字!"
        fi
    done

    while :
    do
        echo
        read -p "是否禁用 IPv6? (默认: 不禁用) (y/n):" yn
        echo
        [ -n "$yn" ] && {
            case ${yn:0:1} in
                y|Y) kcptun_addr="127.0.0.1";;
                n|N) unset kcptun_addr;;
                *  )
                    echo "输入有误, 请重新输入！"
                    continue;;
            esac
        }
        echo "---------------------------"
        [ -z "$kcptun_addr" ] && echo "不禁用IPv6" || echo "禁用IPv6"
        echo "---------------------------"
        break
    done

    # 设置加速的ip地址
    while :
    do
        echo
        echo -e "请输入需要加速的 IP [0.0.0.0 ~ 255.255.255.255]:"
        read -p "(默认: $D_TARGET_IP):" target_ip
        echo
        [ -z "$target_ip" ] && target_ip=$D_TARGET_IP || echo "$target_ip" | \
        grep -qE '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'

        if [ $? -eq 0 ]; then
            echo "---------------------------"
            echo "加速 IP = $target_ip"
            echo "---------------------------"
            break
        else
            echo "IP 地址格式有误, 请重新输入!"
        fi
    done

    # 设置加速的端口
    while :
    do
        echo
        echo -e "请输入需要加速的端口 [1-65535]:"
        read -p "(默认: $D_TARGET_PORT):" target_port
        echo
        [ -z "$target_port" ] && target_port=$D_TARGET_PORT || expr $target_port + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            if [ $target_port -ge 1 -a $target_port -le 65535 ]; then

                if [ "$target_ip" = "$D_TARGET_IP" ]; then
                    $(netstat -an | grep -qE "[0-9:]:${target_port} .+LISTEN") || {
                        read -p "当前没有软件使用此端口, 确定加速此端口?(y/n):" yn
                        case ${yn:0:1} in
                            y|Y) :;;
                            *  ) continue;;
                        esac
                    }
                fi

                echo "---------------------------"
                echo "加速端口 = $target_port"
                echo "---------------------------"
                break
            else
                echo "输入有误, 请输入 1~65535 之间的数字!"
            fi
        else
            echo "输入有误, 请输入数字!"
        fi
    done

    # 设置 Kcptun 密码
    echo
    echo "请输入 Kcptun 密码:"
    read -p "(如果不想使用密码请留空):" kcptun_pwd
    echo
    echo "---------------------------"
    [ -z "$kcptun_pwd" ] && echo "未设置密码" || echo "密码 = $kcptun_pwd"
    echo "---------------------------"

    # 设置加密方式
    while :
    do
        echo
        echo "请选择加密方式(crypt):"
        echo "(1) aes"
        echo "(2) aes-128"
        echo "(3) aes-192"
        echo "(4) salsa20"
        echo "(5) blowfish"
        echo "(6) twofish"
        echo "(7) cast5"
        echo "(8) 3des"
        echo "(9) tea"
        echo "(10) xtea"
        echo "(11) xor"
        echo "(12) none"
        read -p "(请选择 [1~12], 默认: $D_CRYPT):" sel
        echo
        [ -z "$sel" ] && sel=1 || expr $sel + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            case $sel in
                1 ) crypt_methods="aes";;
                2 ) crypt_methods="aes-128";;
                3 ) crypt_methods="aes-192";;
                4 ) crypt_methods="salsa20";;
                5 ) crypt_methods="blowfish";;
                6 ) crypt_methods="twofish";;
                7 ) crypt_methods="cast5";;
                8 ) crypt_methods="3des";;
                9 ) crypt_methods="tea";;
                10) crypt_methods="xtea";;
                11) crypt_methods="xor";;
                12) crypt_methods="none";;
                * )
                    echo
                    echo "请输入有效数字 1~12 !"
                    continue;;
            esac
            echo "-----------------------------"
            echo "加密方式 = $crypt_methods"
            echo "-----------------------------"
            break
        else
            echo "输入有误, 请输入数字！"
        fi
    done

    # Set mode for communication
    while :
    do
        echo
        echo "请选择加速模式(mode):"
        echo "(1) fast3"
        echo "(2) fast2"
        echo "(3) fast"
        echo "(4) normal"
        echo "(5) manual (手动挡)"
        read -p "(请选择 [1~5], 默认: $D_MODE):" sel
        echo
        [ -z "$sel" ] && sel=3 || expr $sel + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            case $sel in
                1 ) comm_mode="fast3";;
                2 ) comm_mode="fast2";;
                3 ) comm_mode="fast";;
                4 ) comm_mode="normal";;
                5 ) comm_mode="manual";;
                * )
                    echo
                    echo "请输入有效数字 1~5 !"
                    continue;;
            esac
            echo "---------------------------"
            echo "加速模式 = $comm_mode"
            echo "---------------------------"
            break
        else
            echo "输入有误, 请输入数字!"
        fi
    done

    [ "$comm_mode" = "manual" ] && {
        while :
        do
            echo
            echo "请设置手动挡参数(预设值或手动设置):"
            echo "(1) 策略1: 通过超时重传＋快速重传, 响应速度优先 (最大化响应时间, 适用于网页访问)"
            echo "(2) 策略2-1: 仅仅通过超时重传, 带宽效率优先 (有效载比优先, 适用于视频观看)"
            echo "(3) 策略2-2: 同上, 与 策略2-1 参数略不相同"
            echo "(4) 策略3: 尽可能通过 FEC 纠删, 最大化传输速度 (较为中庸, 兼顾网页和视频)"
            echo "(5) 手动调整隐藏参数"
            read -p "(请选择 [1~5], 默认: 策略3):" sel
            echo
            [ -z "$sel" ] && sel=3 || expr $sel + 1 &>/dev/null

            if [ $? -eq 0 ]; then
                case $sel in
                    1 )
                        nodelay_value=1
                        resend_value=2
                        nc_value=1
                        interval_value=20
                        unset datashard_value
                        unset parityshard_value;;
                    2 )
                        nodelay_value=1
                        resend_value=0
                        nc_value=1
                        interval_value=40
                        unset datashard_value
                        unset parityshard_value;;
                    3 )
                        nodelay_value=0
                        resend_value=0
                        nc_value=1
                        interval_value=20
                        unset datashard_value
                        unset parityshard_value;;
                    4 )
                        nodelay_value=0
                        resend_value=0
                        nc_value=1
                        interval_value=40
                        datashard_value=5
                        parityshard_value=2;;
                    5 )
                        echo "开始配置隐藏参数..."
                        set_hidden_parameters;;
                    * )
                        echo "请输入有效数字 1~5 !"
                        continue;;
                esac
                echo "---------------------------"
                echo "nodelay = $nodelay_value"
                echo "resend = $resend_value"
                echo "nc = $nc_value"
                echo "interval = $interval_value"
                [ -n "$datashard_value" ] && echo "datashard = $datashard_value"
                [ -n "$parityshard_value" ] && echo "parityshard = $parityshard_value"
                echo "---------------------------"
                break
            else
                echo "输入有误, 请输入数字！"
            fi
        done
    }

    while :
    do
        echo
        echo "请设置 UDP 数据包的 MTU (最大传输单元)值:"
        read -p "(默认: $D_MTU):" mtu_value
        echo
        [ -z "$mtu_value" ] && mtu_value=$D_MTU || expr $mtu_value + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            [ $mtu_value -gt 0 ] && {
                echo "---------------------------"
                echo "MTU = $mtu_value"
                echo "---------------------------"
                break
            } || echo "请输入正数！"
        else
            echo "输入有误, 请输入数字！"
        fi
    done

    while :
    do
        echo
        echo "请设置发送窗口大小(sndwnd):"
        read -p "(数据包数量, 默认: $D_SNDWND):" sndwnd_value
        echo
        [ -z "$sndwnd_value" ] && sndwnd_value=$D_SNDWND || expr $sndwnd_value + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            [ $sndwnd_value -gt 0 ] && {
                echo "---------------------------"
                echo "sndwnd = $sndwnd_value"
                echo "---------------------------"
                break
            } || echo "请输入正数!"
        else
            echo "输入有误, 请输入数字！"
        fi
    done

    while :
    do
        echo
        echo "请设置接收窗口大小(rcvwnd):"
        read -p "(数据包数量, 默认: $D_RCVWND):" rcvwnd_value
        echo
        [ -z "$rcvwnd_value" ] && rcvwnd_value=$D_RCVWND || expr $rcvwnd_value + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            [ $rcvwnd_value -gt 0 ] && {
                echo "---------------------------"
                echo "rcvwnd = $rcvwnd_value"
                echo "---------------------------"
                break
            } || echo "请输入正数!"
        else
            echo "输入有误, 请输入数字!"
        fi
    done

    [ -z "$datashard_value" ] && {
        while :
        do
            echo
            echo "请设置前向纠错 datashard:"
            read -p "(默认: $D_DATASHARD):" datashard_value
            echo
            [ -z "$datashard_value" ] && datashard_value=$D_DATASHARD || expr $datashard_value + 1 &>/dev/null

            if [ $? -eq 0 ]; then
                [ $datashard_value -ge 0 ] && {
                    echo "---------------------------"
                    echo "datashard = $datashard_value"
                    echo "---------------------------"
                    break
                } || echo "请输入大于等于0的数!"
            else
                echo "输入有误, 请输入数字!"
            fi
        done
    }

    [ -z "$parityshard_value" ] && {
        while :
        do
            echo
            echo "请设置前向纠错 parityshard:"
            read -p "(默认: $D_PARITYSHARD):" parityshard_value
            echo
            [ -z "$parityshard_value" ] && parityshard_value=$D_PARITYSHARD || expr $parityshard_value + 1 &>/dev/null

            if [ $? -eq 0 ]; then
                [ $parityshard_value -ge 0 ] && {
                    echo
                    echo "---------------------------"
                    echo "parityshard = $parityshard_value"
                    echo "---------------------------"
                    break
                } || echo "请输入大于等于0的数!"
            else
                echo "输入有误, 请输入数字!"
            fi
        done
    }

    while :
    do
        echo
        echo "请设置差分服务代码点(DSCP):"
        read -p "(默认: $D_DSCP):" dscp_value
        echo
        [ -z "$dscp_value" ] && dscp_value=$D_DSCP || expr $dscp_value + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            [ $dscp_value -ge 0 ] && {
                echo "---------------------------"
                echo "DSCP = $dscp_value"
                echo "---------------------------"
                break
            } || echo "请输入大于等于0的数!"
        else
            echo "输入有误, 请输入数字！"
        fi
    done

    while :
    do
        echo
        read -p "是否禁用数据压缩? (默认: 不禁用) (y/n):" yn
        echo
        [ -z "$yn" ] && yn="n"
        case ${yn:0:1} in
            y|Y) nocomp="true";;
            n|N) nocomp="false";;
            *  )
                echo "输入有误, 请重新输入！"
                continue;;
        esac
        echo "---------------------------"
        [ "$nocomp" = "true" ] && echo "禁用数据压缩" || echo "启用数据压缩"
        echo "---------------------------"
        break
    done

    echo
    echo "配置设置完成, 按任意键继续...或者 Ctrl+C 取消"
    any_key_to_continue
}

function set_hidden_parameters() {
    while :
    do
        echo
        read -p "是否启用 nodelay 模式? (默认: 不启用) (y/n):" yn
        [ -z "$yn" ] && yn="n"
        case ${yn:0:1} in
            y|Y) nodelay_value=1;;
            n|N) nodelay_value=0;;
            *  )
                echo
                echo "输入有误, 请重新输入！"
                continue;;
        esac
        break
    done

    while :
    do
        echo
        echo "是否启用快速重传模式? (resend)"
        echo "(1) 不启用"
        echo "(2) 启用"
        echo "(3) 2次ACK跨越重传"
        read -p "(请选择 [1~3], 默认: 不启用):" sel
        [ -z "$sel" ] && sel=1 || expr $sel + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            case $sel in
                1 ) resend_value=0;;
                2 ) resend_value=1;;
                3 ) resend_value=2;;
                * )
                    echo
                    echo "请输入有效数字 1~3 !"
                    continue;;
            esac
            break
        else
            echo
            echo "输入有误, 请输入数字！"
        fi
    done

    while :
    do
        echo
        read -p "是否关闭流控? (nc) (默认: 不关闭) (y/n):" yn
        [ -z "$yn" ] && yn="n"
        case ${yn:0:1} in
            y|Y) nc_value=1;;
            n|N) nc_value=0;;
            *  )
                echo
                echo "输入有误, 请重新输入！"
                continue;;
        esac
        break
    done

    while :
    do
        echo
        echo "请设置协议内部工作的 interval (单位: ms)"
        read -p "(默认: 20):" interval_value
        echo
        [ -z "$interval_value" ] && interval_value=20 || expr $interval_value + 1 &>/dev/null

        if [ $? -eq 0 ]; then
            [ $interval_value -gt 0 ] && break || echo "请输入大于0的数!"
        else
            echo "输入有误, 请输入数字!"
        fi
    done
}

# 处理配置参数
function analyse_kcptun_config() {
    echo
    echo "正在分析已设置的参数..."
    kcptun_server_config="{\n\t\"listen\": \"${kcptun_addr}:${kcptun_port}\",\n\t\"target\": \"${target_ip}:${target_port}\""
    kcptun_client_config="{\n\t\"localaddr\": \":${target_port}\",\n\t\"remoteaddr\": \"${SERVER_IP}:${kcptun_port}\""
    kcptun_mobile_args="-autoexpire 60"

    [ -n "$kcptun_pwd" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"key\": \"${kcptun_pwd}\""
        kcptun_client_config="${kcptun_client_config},\n\t\"key\": \"${kcptun_pwd}\""
        kcptun_mobile_args="${kcptun_mobile_args} -key \"${kcptun_pwd}\""
    }

    kcptun_server_config="${kcptun_server_config},\n\t\"crypt\": \"${crypt_methods}\""
    kcptun_server_config="${kcptun_server_config},\n\t\"mode\": \"${comm_mode}\""
    kcptun_server_config="${kcptun_server_config},\n\t\"mtu\": ${mtu_value}"
    kcptun_server_config="${kcptun_server_config},\n\t\"sndwnd\": ${sndwnd_value}"
    kcptun_server_config="${kcptun_server_config},\n\t\"rcvwnd\": ${rcvwnd_value}"
    kcptun_server_config="${kcptun_server_config},\n\t\"datashard\": ${datashard_value}"
    kcptun_server_config="${kcptun_server_config},\n\t\"parityshard\": ${parityshard_value}"
    kcptun_server_config="${kcptun_server_config},\n\t\"dscp\": ${dscp_value}"

    kcptun_client_config="${kcptun_client_config},\n\t\"crypt\": \"${crypt_methods}\""
    kcptun_client_config="${kcptun_client_config},\n\t\"mode\": \"${comm_mode}\""
    kcptun_client_config="${kcptun_client_config},\n\t\"mtu\": ${mtu_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"sndwnd\": ${rcvwnd_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"rcvwnd\": ${sndwnd_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"datashard\": ${datashard_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"parityshard\": ${parityshard_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"dscp\": ${dscp_value}"
    kcptun_client_config="${kcptun_client_config},\n\t\"conn\": 1"
    kcptun_client_config="${kcptun_client_config},\n\t\"autoexpire\": 60"

    [ "$crypt_methods" != "$D_CRYPT" ] && kcptun_mobile_args="${kcptun_mobile_args} -crypt \"${crypt_methods}\""
    [ "$comm_mode" != "$D_MODE" ] && kcptun_mobile_args="${kcptun_mobile_args} -mode \"${comm_mode}\""
    [ "$mtu_value" != "$D_MTU" ] && kcptun_mobile_args="${kcptun_mobile_args} -mtu ${mtu_value}"
    [ "$datashard_value" != "$D_DATASHARD" ] && kcptun_mobile_args="${kcptun_mobile_args} -datashard ${datashard_value}"
    [ "$parityshard_value" != "$D_PARITYSHARD" ] && kcptun_mobile_args="${kcptun_mobile_args} -parityshard ${parityshard_value}"
    [ "$dscp_value" != "$D_DSCP" ] && kcptun_mobile_args="${kcptun_mobile_args} -dscp ${dscp_value}"

    [ -n "$nodelay_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"nodelay\": ${nodelay_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"nodelay\": ${nodelay_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -nodelay ${nodelay_value}"
    }
    [ -n "$resend_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"resend\": ${resend_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"resend\": ${resend_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -resend ${resend_value}"
    }
    [ -n "$nc_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"nc\": ${nc_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"nc\": ${nc_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -nc ${nc_value}"
    }
    [ -n "$interval_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"interval\": ${interval_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"interval\": ${interval_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -interval ${interval_value}"
    }
    [ -n "$sockbuf_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"sockbuf\": ${sockbuf_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"sockbuf\": ${sockbuf_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -sockbuf ${sockbuf_value}"
    }
    [ -n "$keepalive_value" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"keepalive\": ${keepalive_value}"
        kcptun_client_config="${kcptun_client_config},\n\t\"keepalive\": ${keepalive_value}"
        kcptun_mobile_args="${kcptun_mobile_args} -keepalive ${keepalive_value}"
    }
    [ -n "$acknodelay" ] && {
        kcptun_server_config="${kcptun_server_config},\n\t\"acknodelay\": ${acknodelay}"
        kcptun_client_config="${kcptun_client_config},\n\t\"acknodelay\": ${acknodelay}"
        kcptun_mobile_args="${kcptun_mobile_args} -acknodelay ${acknodelay_value}"
    }

    kcptun_server_config="${kcptun_server_config},\n\t\"nocomp\": ${nocomp}"
    kcptun_client_config="${kcptun_client_config},\n\t\"nocomp\": ${nocomp}"
    [ "$nocomp" = "true" ] && kcptun_mobile_args="${kcptun_mobile_args} -nocomp"

    kcptun_server_config="${kcptun_server_config}\n}"
    kcptun_client_config="${kcptun_client_config}\n}"
}


# 安装需要的依赖软件
function install_dependence() {
    echo
    echo "正在安装依赖软件..."
    if [ "$OS" = "CentOS" ]; then
        yum makecache
        yum --disablerepo=epel update -y ca-certificates || yum update -y ca-certificates
        yum install -y epel-release
        yum --enablerepo=epel install -y curl wget jq python-setuptools tar
        [ "$OS_VSRSION" -eq 7 ] && yum -y install net-tools
    else
        apt-get -y update
        apt-get -y install curl wget jq python-setuptools tar || {
            [ "$OS" = "Ubuntu" ] && {
                echo "deb http://archive.ubuntu.com/ubuntu vivid main universe" >> /etc/apt/sources.list
            } || {
                echo "deb http://ftp.debian.org/debian wheezy-backports main contrib non-free" >> /etc/apt/sources.list
            }
            apt-get -y update
            apt-get -y install curl wget jq python-setuptools tar || {
                echo
                echo "安装依赖软件包失败!"
                exit_with_error $E_INSTALL_DEPENDENCE
            }
        }
    fi

    easy_install supervisor || {
        echo
        echo "安装 Supervisor 失败!"
        exit_with_error $E_INSTALL_DEPENDENCE
    }

    [ -d /etc/supervisor/conf.d ] || {
        mkdir -p /etc/supervisor/conf.d || {
            echo
            echo "创建 Supervisor 配置文件目录失败!"
            exit_with_error $E_CREATE_DIR
        }
    }

    [ -s /etc/supervisor/supervisord.conf ] || {
        echo_supervisord_conf > /etc/supervisor/supervisord.conf
        [ $? -ne 0 ] && {
            echo
            echo "创建 Supervisor 配置文件失败!"
            exit_with_error $E_CREATE_FILE
        }
    }
}

# 通过网络获取需要的信息
function get_kcptun_version_info() {
    echo
    echo "正在获取网络信息..."
    local request_version=$1

    local kcptun_release_content
    [ -n "$request_version" ] && {
        kcptun_release_content=$(curl --silent --insecure --fail $KCPTUN_RELEASES_URL | jq -r ".[] | select(.tag_name == \"${request_version}\")")
    } || {
        kcptun_release_content=$(curl --silent --insecure --fail $KCPTUN_RELEASES_URL | jq -r ".[0]")
    }

    if [ -n "$kcptun_release_content" ]; then
        kcptun_release_name=$(echo "$kcptun_release_content" | jq -r ".name")
        kcptun_release_tag_name=$(echo "$kcptun_release_content" | jq -r ".tag_name")
        kcptun_release_prerelease=$(echo "$kcptun_release_content" | jq -r ".prerelease")
        kcptun_release_html_url=$(echo "$kcptun_release_content" | jq -r ".html_url")

        kcptun_release_download_url=$(echo "$kcptun_release_content" | jq -r ".assets[] | select(.name | contains(\"$SPRUCE_TYPE\")) | .browser_download_url" | head -n 1) || {
            echo
            echo "获取 Kcptun 下载地址失败, 请重试..."
            exit_with_error $E_NETWORK
        }
    else
        [ -n "$request_version" ] && {
            return $E_WRONG_TAG
        } || {
            echo
            echo "获取 Kcptun 版本信息失败, 请检查你的网络连接！"
            exit_with_error $E_NETWORK
        }
    fi
}

# 获取shell脚本更新
function get_shell_version_info() {
    local shell_version_content=$(curl --silent --insecure --fail $SHELL_VERSION_INFO_URL) && {
        new_shell_version=$(echo "$shell_version_content" | jq -r ".shell_version" | grep -oE "[0-9]+")
        new_config_version=$(echo "$shell_version_content" | jq -r ".config_version" | grep -oE "[0-9]+")
        new_init_version=$(echo "$shell_version_content" | jq -r ".init_version" | grep -oE "[0-9]+")

        shell_change_log=$(echo "$shell_version_content" | jq -r ".change_log")
        config_change_log=$(echo "$shell_version_content" | jq -r ".config_change_log")
        init_change_log=$(echo "$shell_version_content" | jq -r ".init_change_log")

        new_shell_url=$(echo "$shell_version_content" | jq -r ".shell_url")
    } || {
        new_shell_version=0
        new_config_version=0
        new_init_version=0
    }
}

# 下载文件
function download_file(){
    echo
    echo "开始下载文件..."
    cd "$CUR_DIR"
    [ `pwd` != "$CUR_DIR" ] && {
        echo
        echo "切换目录失败..."
        exit_with_error $E_XCD
    }

    $(curl -L -C - -o "kcptun-$kcptun_release_tag_name.tar.gz" "$kcptun_release_download_url") || {
        echo
        echo "下载 Kcptun 文件失败！"
        exit_with_error $E_DOWNLOAD_FAILED
    }
}

function unpack_file() {
    echo
    echo "开始解压文件..."
    cd "$CUR_DIR"
    [ -d "$KCPTUN_INSTALL_DIR" ] || mkdir -p "$KCPTUN_INSTALL_DIR"
    tar -zxf "kcptun-$kcptun_release_tag_name.tar.gz" -C "$KCPTUN_INSTALL_DIR"

    local kcptun_server_exec="$KCPTUN_INSTALL_DIR"/server_"$FILE_SUFFIX"
    [ -f "$kcptun_server_exec" ] && {
        chmod a+x "$kcptun_server_exec" || {
            echo
            echo "无法设置执行权限..."
            exit_with_error $E_NOTROOT
        }
    } || {
        echo
        echo "解压安装文件失败!"
        exit_with_error $E_FILE_NOT_FOUND
    }
}

# 创建配置文件
function config_kcptun(){
    echo
    echo "正在写入配置..."
    if [ -f /etc/supervisor/supervisord.conf ]; then
        # sed -i 's/^\[include\]$/&\nfiles = \/etc\/supervisor\/conf.d\/\*\.conf/;t;$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf

        $(grep -q "^files\s*=\s*\/etc\/supervisor\/conf\.d\/\*\.conf$" /etc/supervisor/supervisord.conf) || {
            $(grep -q "^\[include\]$" /etc/supervisor/supervisord.conf) && {
                sed -i '/^\[include\]$/a files = \/etc\/supervisor\/conf.d\/\*\.conf' /etc/supervisor/supervisord.conf
            } || {
                sed -i '$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf
            }
        }

        # 创建文件夹
        [ -d "$KCPTUN_INSTALL_DIR" ] || mkdir -p "$KCPTUN_INSTALL_DIR"

        echo -e "$kcptun_server_config" > "$KCPTUN_INSTALL_DIR"/server-config.json

        cat > /etc/supervisor/conf.d/kcptun.conf<<-EOF
[program:kcptun]
directory=${KCPTUN_INSTALL_DIR}
command=${KCPTUN_INSTALL_DIR}/server_${FILE_SUFFIX} -c ${KCPTUN_INSTALL_DIR}/server-config.json
process_name=%(program_name)s
autostart=true
redirect_stderr=true
stdout_logfile=${KCPTUN_LOG_FILE}
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=0
EOF
    else
        echo
        echo "未找到 Supervisor 配置文件！"
        exit_with_error $E_FILE_NOT_FOUND
    fi
}

function downlod_init_script() {
    echo
    echo "开始下载服务脚本..."

    local init_file_url
    [ "$OS" = "CentOS" ] && {
        init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/redhat.init"
    } || {
        init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/ubuntu.init"
    }

    if ! $(wget --no-check-certificate -O /etc/init.d/supervisord "$init_file_url"); then
        echo
        echo "下载 Supervisor 自启脚本失败！"
        exit_with_error $E_DOWNLOAD_FAILED
    fi

    chmod a+x /etc/init.d/supervisord

    [ -x /etc/init.d/supervisord ] || {
        echo
        echo "设置可执行权限失败..."

        exit_with_error $E_NOTROOT
    }
}

# 安装服务
function install_service() {
    echo
    echo "正在配置系统服务..."

    [ "$OS" = "CentOS" ] && {
        chkconfig --add supervisord
        chkconfig supervisord on
    } || {
        update-rc.d -f supervisord defaults
    }

    service supervisord restart && {
        sleep 3
        supervisorctl reload
        supervisorctl restart kcptun || {
            echo
            echo "启动 Kcptun 服务端失败！"
            exit_with_error
        }
    } || {
        echo
        echo "启动 Supervisord 失败！"
        exit_with_error
    }
}

# 安装清理
function install_cleanup() {
    echo
    echo "正在清理无用文件..."
    cd "$CUR_DIR"
    rm -f "kcptun-$kcptun_release_tag_name.tar.gz"
    rm -f "$KCPTUN_INSTALL_DIR"/client_"$FILE_SUFFIX"
}

# 获取当前安装的 kcptun 版本
function get_installed_version() {
    local kcptun_server_exec="$KCPTUN_INSTALL_DIR"/server_"$FILE_SUFFIX"
    if [ -x "$kcptun_server_exec" ]; then
        installed_kcptun_version=$($kcptun_server_exec --version | grep -oE "[0-9]+")
    else
        unset installed_kcptun_version
        echo
        echo "未找到已安装的 Kcptun 服务端执行文件, 或许你并没有安装 Kcptun?"
        exit_with_error
    fi
}

# 显示安装信息
function show_config_info() {
    echo
    echo -e "服务器IP: \033[41;37m ${SERVER_IP} \033[0m"
    echo -e "端口: \033[41;37m ${kcptun_port} \033[0m"
    echo -e "加速地址: ${target_ip}:${target_port}"
    [ -n "$kcptunpwd" ] && echo -e "密码: \033[41;37m ${kcptun_pwd} \033[0m"
    [ "$crypt_methods" != "$D_CRYPT" ] && echo -e "加密方式 Crypt: \033[41;37m ${crypt_methods} \033[0m"
    [ "$comm_mode" != "$D_MODE" ] && echo -e "加速模式 Mode: \033[41;37m ${comm_mode} \033[0m"
    [ "$mtu_value" != "$D_MTU" ] && echo -e "MTU: \033[41;37m ${mtu_value} \033[0m"
    [ "$sndwnd_value" != "$D_SNDWND" ] && echo -e "发送窗口大小 Sndwnd: \033[41;37m ${sndwnd_value} \033[0m"
    [ "$rcvwnd_value" != "$D_RCVWND" ] && echo -e "接受窗口大小 Rcvwnd: \033[41;37m ${rcvwnd_value} \033[0m"
    [ "$nocomp" = "true" ] && echo -e "数据压缩: \033[41;37m 已禁用 \033[0m"
    [ "$datashard_value" != "$D_DATASHARD" ] && echo -e "前向纠错 Datashard: \033[41;37m ${datashard_value} \033[0m"
    [ "$parityshard_value" != "$D_PARITYSHARD" ] && echo -e "前向纠错 Parityshard: \033[41;37m ${parityshard_value} \033[0m"
    [ "$dscp_value" != "$D_DSCP" ] && echo -e "差分服务代码点 DSCP: \033[41;37m ${dscp_value} \033[0m"
    echo
    [ -n "$installed_kcptun_version" ] && echo "当前安装的 Kcptun 版本为: v$installed_kcptun_version"
    [ -n "$kcptun_release_html_url" ] && echo "请前往 $kcptun_release_html_url 手动下载客户端文件"
    echo
    echo "推荐的客户端配置为: "
    echo -e "$kcptun_client_config"
    echo
    echo "手机端参数可以使用："
    echo -e "$kcptun_mobile_args"
    echo
    echo "其他参数请自行计算或设置, 详细信息可以查看: https://github.com/xtaci/kcptun"
    echo
    echo -e "Kcptun 安装目录: ${KCPTUN_INSTALL_DIR}"
    echo -e "Kcptun 配置文件: ${KCPTUN_INSTALL_DIR}/server-config.json"
    echo -e "Kcptun 日志文件: ${KCPTUN_LOG_FILE}"
    echo
    echo "Supervisor {启动|关闭|重启|查看状态} 命令: service supervisord {start|stop|restart|status}"
    echo "Kcptun 服务端 {启动|关闭|重启|查看状态} 命令: supervisorctl {start|stop|restart|status} kcptun"
    echo "已将 Supervisor 加入开机自启, Kcptun 服务端会随 Supervisor 的启动而启动"
    echo
    echo -e "如需 {重新配置|更新|卸载} 服务端, 请使用: $0 {reconfig|update|uninstall}"
    echo
    echo "欢迎访问扩软博客: https://blog.kuoruan.com/"
    echo
    echo "我们的QQ群: 43391448"
    echo
    echo "尽情使用吧！"
    echo
}

# 更新脚本TAG Name
function update_tag_name() {
    local tag_name=${1:-$kcptun_release_tag_name}
    [ -n "$tag_name" ] && {
        sed -i "s/^KCPTUN_TAG_NAME=.*/KCPTUN_TAG_NAME=\"${tag_name}\"/" "$0"
    }
}

# 安装 Kcptun
function install_kcptun(){
    permission_check
    linux_check
    installed_check
    disable_selinux
    get_arch
    get_server_ip
    set_kcptun_config
    analyse_kcptun_config
    install_dependence
    get_kcptun_version_info
    download_file
    unpack_file
    config_kcptun
    downlod_init_script
    install_service
    update_tag_name
    install_cleanup
    get_installed_version
    show_config_info
}

# 重新下载 kcptun
function update_kcptun() {
    download_file
    unpack_file
    touch "$KCPTUN_LOG_FILE" && echo > "$KCPTUN_LOG_FILE"
    service supervisord restart
    sleep 3
    update_tag_name
    install_cleanup
    echo
    echo "已安装 Kcptun 服务端版本 ${kcptun_release_tag_name}"
    [ -n "$kcptun_release_html_url" ] && {
        echo
        echo "请前往 $kcptun_release_html_url 手动下载客户端文件"
    }
}

function manual_install() {
    permission_check
    linux_check
    get_arch

    local tag_name=$1
    [ -z "$tag_name" ] && {
        while :
        do
            echo
            read -p "请输入你想安装的 Kcptun 版本 TAG, 例如: v20160902:" tag_name
            if $(echo "$tag_name" | grep -qE "\w+"); then
                local version_num
                version_num=$(echo "$tag_name" | grep -oE "[0-9]+") || version_num=0
                [ $(echo ${#version_num}) -eq 8 -a $version_num -le 20160826 ] && {
                    echo
                    echo "暂不支持安装 v20160826 及以前版本"
                    continue
                }

                get_kcptun_version_info $tag_name
                if [ $? -eq $E_WRONG_TAG ]; then
                    echo
                    echo "未找到对应版本下载地址, 你输入的 TAG 为: $tag_name , 请重新输入!"
                    echo "你可以前往: $KCPTUN_TAGS_URL 查看所有可用 Tag"
                    continue
                else
                    echo
                    echo "已找到 Kcptun 版本信息, TAG: $tag_name"
                    echo "请按任意键继续安装..."
                    any_key_to_continue
                    update_kcptun
                    break
                fi
            else
                echo "输入无效, 请重新输入!"
                continue
            fi
        done
    }
}

# 显示配置信息
function show_cur_config() {
    permission_check
    linux_check
    get_arch
    get_installed_version
    echo
    [ -n "$installed_kcptun_version" ] && echo "当前安装的 Kcptun 版本为: v$installed_kcptun_version"
    echo

    local config_file="$KCPTUN_INSTALL_DIR/"server-config.json
    [ -f "$config_file" ] && cat $config_file || echo "未找到配置文件..."
}

# 检查更新
function check_update() {
    permission_check
    linux_check
    echo
    echo "开始检查更新..."

    local shell_path=$0
    get_shell_version_info

    if [ -n "$new_shell_version" -a $new_shell_version -gt $SHELL_VERSION ]; then
        echo
        echo "发现一键安装脚本更新, 版本号: v${new_shell_version}"
        echo -e "更新说明: \n${shell_change_log}"
        echo
        echo "按任意键开始更新, 或者 Ctrl+C 取消"
        any_key_to_continue
        echo
        echo "正在更新一键安装脚本..."
        mv -f "$shell_path" "$shell_path".bak

        $(wget --no-check-certificate -O "$shell_path" "$new_shell_url") && {
            chmod a+x "$shell_path"
            sed -i -r "s/^CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
            sed -i -r "s/^INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
            rm -f "$shell_path".bak
            clear
            echo
            echo "安装脚本已更新到 v${new_shell_version}, 正在运行新的脚本..."

            bash $shell_path update
            exit $SUCCESS
        } || {
            mv -f "$shell_path".bak $shell_path
            echo
            echo "下载新的一键安装脚本失败..."
        }
    else
        echo
        echo "未发现一键安装脚本更新..."
    fi

    get_arch
    get_installed_version
    get_kcptun_version_info

    local cur_tag_name
    if [ -n "$KCPTUN_TAG_NAME" ]; then
        local tag_version
        tag_version=$(echo "$KCPTUN_TAG_NAME" | grep -oE "[0-9]+") || tag_version=0
        if [ $tag_version -gt $installed_kcptun_version ]; then
            cur_tag_name=v"$installed_kcptun_version"
            update_tag_name $cur_tag_name
        else
            cur_tag_name=$KCPTUN_TAG_NAME
        fi
    else
        cur_tag_name=v"$installed_kcptun_version"
        update_tag_name $cur_tag_name
    fi

    if [ -n "$kcptun_release_tag_name" -a "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
        echo "发现 Kcptun 新版本 ${kcptun_release_tag_name}"
        echo -e "更新说明: \n${kcptun_release_name}"
        echo
        [ "$kcptun_release_prerelease" = "true" ] && echo -e "\033[41;37m 注意: 该版本为预览版, 可能会出现各种问题 \033[0m"
        echo "按任意键开始更新, 或者 Ctrl+C 取消"
        any_key_to_continue
        echo "正在自动更新 Kcptun..."
        update_kcptun
    else
        echo
        echo "未发现 Kcptun 更新..."
    fi

    if [ -n "$new_config_version" -a $new_config_version -gt $CONFIG_VERSION ]; then
        echo
        echo "发现 Kcptun 配置更新, 版本号: v${new_config_version}, 需要重新设置 Kcptun..."
        echo -e "更新说明: \n${config_change_log}"
        echo
        echo "按任意键开始配置, 或者 Ctrl+C 取消"
        any_key_to_continue
        reconfig_kcptun
        sed -i "s/^CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" "$shell_path"
    else
        echo
        echo "未发现 Kcptun 配置更新..."
    fi

    if [ -n "$new_init_version" -a $new_init_version -gt $INIT_VERSION ]; then
        echo
        echo "发现服务启动脚本文件更新, 版本号: v${new_init_version}"
        echo -e "更新说明: \n${init_change_log}"
        echo
        echo "按任意键开始更新, 或者 Ctrl+C 取消"
        click_to_continue
        echo
        echo "正在自动更新启动脚本..."
        downlod_init_script
        [ "$OS" = "CentOS" -a $OS_VSRSION -eq 7 ] && systemctl daemon-reload

        sed -i "s/^INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" "$shell_path"
        echo
        echo "服务启动脚本已更新到 v${new_init_version}, 可能需要重启服务器才能生效!"
    else
        echo
        echo "未发现服务启动脚本更新..."
    fi
}

# 卸载 Kcptun
function uninstall_kcptun(){
    permission_check
    linux_check
    echo
    echo "是否卸载 Kcptun 服务端? 按任意键继续...或者 Ctrl+C 取消"
    any_key_to_continue
    echo
    echo "正在卸载 Kcptun 服务端并取消 Supervisor 的开机启动..."
    supervisorctl stop kcptun
    service supervisord stop

    [ "$OS" = "CentOS" ] && chkconfig supervisord off || update-rc.d -f supervisord remove

    rm -f /etc/supervisor/conf.d/kcptun.conf
    rm -rf $KCPTUN_INSTALL_DIR
    rm -f $KCPTUN_LOG_FILE
    echo
    echo "Kcptun 服务端卸载完成！欢迎再次使用。"
}

# 重新配置
function reconfig_kcptun() {
    permission_check
    linux_check
    get_server_ip
    get_arch
    set_kcptun_config
    analyse_kcptun_config
    echo
    echo "正在写入新的配置..."
    config_kcptun

    touch "$KCPTUN_LOG_FILE" && echo > "$KCPTUN_LOG_FILE"

    [ -x /etc/init.d/supervisord ] && {
        service supervisord restart || echo "重启 Kcptun 失败, 请手动检查！"
    } || {
        echo
        echo "未找到 Supervisor 服务, 无法重启 Kcptun 服务端, 请手动检查！"
    }
    echo
    echo "恭喜, Kcptun 服务端配置完毕！"
    get_installed_version
    show_config_info
}

# 初始化脚本动作
action=${1:-"install"}
case $action in
    install)
        install_kcptun
        ;;
    uninstall)
        uninstall_kcptun
        ;;
    update)
        check_update
        ;;
    reconfig)
        reconfig_kcptun
        ;;
    manual)
        manual_install $2
        ;;
    show)
        show_cur_config
        ;;
    *)
        echo "参数错误！ [${action}]"
        echo "请使用: $0 {install|uninstall|update|reconfig|manual|show}"
        ;;
esac

exit $SUCCESS
