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

SHELL_VERSION=4
CONFIG_VERSION=2
INIT_VERSION=1

clear
echo
echo "#############################################################"
echo "# Kcptun Server 一键安装脚本                                #"
echo "# 该脚本支持 Kcptun Server 的安装、更新、卸载及配置         #"
echo "# 官方网站: https://blog.kuoruan.com/                       #"
echo "# 作者: Index <kuoruan@gmail.com>                           #"
echo "# 致谢: 脚本编写过程中参考了 @teddysun 的SS一键安装脚本     #"
echo "# QQ交流群: 43391448                                        #"
echo "#############################################################"
echo

# Get current dir
CUR_DIR=`pwd`

# Get public IP address
IP=$(ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1)
[ -z "$IP" ] && IP=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)

# Make sure only root can run our script
function rootness(){
	if [ $EUID -ne 0 ]; then
		echo "权限错误, 请使用 root 用户运行此脚本！"
		exit 1
	fi
}

# Check OS
function checkos(){
	if [ -f /etc/redhat-release ]; then
		OS='CentOS'
	elif [ ! -z "`cat /etc/issue | grep bian`" ]; then
		OS='Debian'
	elif [ ! -z "`cat /etc/issue | grep Ubuntu`" ]; then
		OS='Ubuntu'
	else
		echo "暂不支持此系统, 请重装系统后重试！"
		exit_shell
	fi
}

# Get mechine type
function get_machine_type(){
	local type=`uname -m`;
	[ -z "$type" ] && type=`getconf LONG_BIT`;
	if [[ "$type" == *'64'* ]]; then
		SPRUCE_TYPE='linux-amd64'
		FILE_SUFFIX='linux_amd64'
	else
		SPRUCE_TYPE='linux-386'
		FILE_SUFFIX='linux_386'
	fi
}

# CentOS version
function centosversion(){
	if [ "$OS" == 'CentOS' ]; then
		local code=$1
		local version="`get_osversion`"
		local main_ver=${version%%.*}
		if [ $main_ver == $code ]; then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
}

# Get OS version
function get_osversion(){
	if [ -s /etc/redhat-release ]; then
		grep -oE "[0-9.]+" /etc/redhat-release
	else
		grep -oE "[0-9.]+" /etc/issue
	fi
}

# Disable selinux
function disable_selinux(){
	if [ -s /etc/selinux/config ] && grep -q 'SELINUX=enforcing' /etc/selinux/config; then
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
		setenforce 0
	fi
}

# Exit shell
function exit_shell(){
	echo
	echo "Kcptun Server 安装失败！"
	echo "希望你能记录下错误信息, 然后将错误信息发送给我"
	echo "我的邮箱: kuoruan@gmail.com"
	echo "欢迎加入我们的QQ群: 43391448"
	echo "扩软博客：https://blog.kuoruan.com"
	echo
	exit 1
}

function click_to_continue(){
	get_char(){
		SAVEDSTTY=`stty -g`
		stty -echo
		stty cbreak
		dd if=/dev/tty bs=1 count=1 2> /dev/null
		stty -raw
		stty echo
		stty $SAVEDSTTY
	}
	char=`get_char`
}

check_install() {
	if [ -f /etc/supervisor/supervisord.conf -a -d /usr/share/kcptun/ ]; then
		echo "似乎你曾经安装过 Kcptun Server"
		echo
		while true
		do
			echo "请选择你希望的操作:"
			echo "(1) 覆盖安装"
			echo "(2) 重新配置"
			echo "(3) 检查更新"
			echo "(4) 卸载"
			echo "(5) 退出"
			read -p "(请选择 [1~5], 默认: 覆盖安装):" sel
			if [ -z "$sel" ]; then
				echo "开始覆盖安装 Kcptun Server..."
				echo
				return
			else
				expr $sel + 0 &> /dev/null
				if [ $? -eq 0 ]; then
					case $sel in
						1)
							echo "开始覆盖安装 Kcptun Server..."
							echo
							return
							;;
						2)
							reconfig_kcptun
							exit 0
							;;
						3)
							check_update
							exit 0
							;;
						4)
							uninstall_kcptun
							exit 0
							;;
						5)
							exit 0;;
						*)
							echo "请输入有效数字(1~4)！"
							continue;;
					esac
				else
					echo "输入有误, 请输入数字！"
				fi
			fi
		done
	fi
}

function set_config(){
	# Not support CentOS 5
	if centosversion 5; then
		echo "暂不支持 CentOS5, 请重装系统为 CentOS 6+, Debian 7+ 或者 Ubuntu 12+ 并重试!"
		exit_shell
	fi

	local port_stat=""
	local sel=""
	# Set Kcptun config port
	while true
	do
		echo -e "请输入 Kcptun Server 端口 [1-65535]:"
		read -p "(默认: 554):" kcptunport
		[ -z "$kcptunport" ] && kcptunport="554"
		expr $kcptunport + 0 &>/dev/null
		if [ $? -eq 0 ]; then
			if [ $kcptunport -ge 1 ] && [ $kcptunport -le 65535 ]; then
				port_stat=`netstat -an | grep -E "[0-9:]:${kcptunport} .+LISTEN"`
				if [ -z "$port_stat" ]; then
					echo
					echo "---------------------------"
					echo "端口 = $kcptunport"
					echo "---------------------------"
					echo
					break
				else
					echo "端口已被占用, 请重新输入！"
				fi
			else
				echo "输入有误, 请输入 1~65535 之间的数字！"
			fi
		else
			echo "输入有误, 请输入数字！"
		fi
	done

	# Set Kcptun forward port
	while true
	do
		echo -e "请输入需要加速的 IP [0.0.0.0 ~ 255.255.255.255]:"
		read -p "(默认: 127.0.0.1):" forwardip
		[ -z "$forwardip" ] && forwardip="127.0.0.1"
		echo "$forwardip" | grep -qE '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
		if [ $? -eq 0 ]; then
			echo
			echo "---------------------------"
			echo "加速 IP = $forwardip"
			echo "---------------------------"
			echo
			break
		else
			echo "输入有误, 请输入正确的 IP 地址！"
		fi
	done

	# Set Kcptun forward port
	while true
	do
		echo -e "请输入需要加速的端口 [1-65535]:"
		read -p "(默认: 8388):" forwardport
		[ -z "$forwardport" ] && forwardport="8388"
		expr $forwardport + 0 &>/dev/null
		if [ $? -eq 0 ]; then
			if [ $forwardport -ge 1 ] && [ $forwardport -le 65535 ]; then
				port_stat=`netstat -an | grep -E "[0-9:]:${forwardport} .+LISTEN"`
				if [ -z "$port_stat" ]; then
					read -p "当前没有软件使用此端口, 确定加速此端口?(y/n)" yn
					case ${yn:0:1} in
						y|Y) ;;
						*) continue;;
					esac
				fi
				echo
				echo "---------------------------"
				echo "加速端口 = $forwardport"
				echo "---------------------------"
				echo
				break
			else
				echo "输入有误, 请输入 1~65535 之间的数字！"
			fi
		else
			echo "输入有误, 请输入数字！"
		fi
	done

	# Set Kcptun config password
	echo "请输入 Kcptun 密码:"
	read -p "(如果不想使用密码请留空):" kcptunpwd
	echo
	echo "---------------------------"
	if [ -z "$kcptunpwd" ]; then
		echo "未设置密码"
	else
		echo "密码 = $kcptunpwd"
	fi
	echo "---------------------------"
	echo

	# Set methods for encryption
	while true
	do
		echo "请选择加密方式:"
		echo "(1) aes"
		echo "(2) tea"
		echo "(3) xor"
		echo "(4) none"
		read -p "(请选择 [1~4], 默认: aes):" sel
		if [ -z "$sel" ]; then
			echo
			echo "-----------------------------"
			echo "将使用默认加密方式"
			echo "-----------------------------"
			echo
			break
		else
			expr $sel + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				case $sel in
					1) crypt_methods="aes";;
					2) crypt_methods="tea";;
					3) crypt_methods="xor";;
					4) crypt_methods="none";;
					*)
						echo "请输入有效数字(1~4)！"
						continue;;
				esac
				echo
				echo "-----------------------------"
				echo "加密方式 = $crypt_methods"
				echo "-----------------------------"
				echo
				break
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	# Set mode for communication
	while true
	do
		echo "请选择加速模式 (越快越浪费带宽):"
		echo "(1) fast3"
		echo "(2) fast2"
		echo "(3) fast"
		echo "(4) normal"
		read -p "(请选择 [1~4], 默认: fast):" sel
		if [ -z "$sel" ]; then
			echo
			echo "---------------------------"
			echo "将使用默认加速模式"
			echo "---------------------------"
			echo
			break
		else
			expr $sel + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				case $sel in
					1) comm_mode="fast3";;
					2) comm_mode="fast2";;
					3) comm_mode="fast";;
					4) comm_mode="normal";;
					*)
						echo "请输入有效数字(1~4)！"
						continue;;
				esac
				echo
				echo "---------------------------"
				echo "加速模式 = $comm_mode"
				echo "---------------------------"
				echo
				break
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		echo "请设置 UDP 数据包的 MTU (最大传输单元)值:"
		read -p "(默认: 1350):" mtu_value
		if [ -z "$mtu_value" ]; then
			echo
			echo "---------------------------"
			echo "MTU 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $mtu_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $mtu_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "MTU = $mtu_value"
					echo "---------------------------"
					echo
					break
				else
					echo "请输入正数！"
				fi
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		echo "请设置发送窗口大小(sndwnd):"
		read -p "(数据包数量, 默认: 1024):" sndwnd_value
		if [ -z "$sndwnd_value" ]; then
			echo
			echo "---------------------------"
			echo "Sndwnd 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $sndwnd_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $sndwnd_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "Sndwnd = $sndwnd_value"
					echo "---------------------------"
					echo
					break
				else
					echo "请输入正数！"
				fi
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		echo "请设置接收窗口大小(rcvwnd):"
		read -p "(数据包数量, 默认: 1024):" rcvwnd_value
		if [ -z "$rcvwnd_value" ]; then
			echo
			echo "---------------------------"
			echo "Rcvwnd 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $rcvwnd_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $rcvwnd_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "Rcvwnd = $rcvwnd_value"
					echo "---------------------------"
					echo
					break
				else
					echo "请输入正数！"
				fi
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		read -p "是否禁用数据压缩? (默认: 不禁用) (y/n)):" yn
		[ -z "$yn" ] && yn="n"
		case ${yn:0:1} in
			y|Y) nocomp="y";;
			n|N) nocomp="";;
			*)
				echo "输入有误, 请重新输入！"
				continue;;
		esac
		echo
		echo "---------------------------"
		if [ "$nocomp" == "y" ]; then
			echo "数据压缩将被禁用！"
		else
			echo "将启用数据压缩！"
		fi
		echo "---------------------------"
		echo
		break
	done

	while true
	do
		echo "请设置前向纠错 Datashard:"
		read -p "(默认: 10):" datashard_value
		if [ -z "$datashard_value" ]; then
			echo
			echo "---------------------------"
			echo "Datashard 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $datashard_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $datashard_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "Datashard = $datashard_value"
					echo "---------------------------"
					echo
					break
				else
					echo "请输入正数！"
				fi
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		echo "请设置前向纠错 Parityshard:"
		read -p "(默认: 3):" parityshard_value
		if [ -z "$parityshard_value" ]; then
			echo
			echo "---------------------------"
			echo "Parityshard 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $parityshard_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $parityshard_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "Parityshard = $parityshard_value"
					echo "---------------------------"
					echo
					break
				else
					echo "请输入正数！"
				fi
			else
				echo "输入有误, 请输入数字！"
			fi
		fi
	done

	while true
	do
		echo "请设置差分服务代码点 DSCP:"
		read -p "(默认: 0):" dscp_value
		if [ -z "$dscp_value" ]; then
			echo
			echo "---------------------------"
			echo "DSCP 将使用默认值"
			echo "---------------------------"
			echo
			break
		else
			expr $dscp_value + 0 &> /dev/null
			if [ $? -eq 0 ]; then
				if [ $dscp_value -gt 0 ]; then
					echo
					echo "---------------------------"
					echo "DSCP = $dscp_value"
					echo "---------------------------"
					echo
					break
				fi
			else
				echo "输入有误, 请输入大于0的数字, 或直接回车！"
			fi
		fi
	done

	KCPTUN_SERVER_ARGS="-t \"${forwardip}:${forwardport}\" -l \":${kcptunport}\""
	[ -n "$kcptunpwd" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --key \"${kcptunpwd}\""
	[ -n "$crypt_methods" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --crypt ${crypt_methods}"
	[ -n "$comm_mode" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --mode ${comm_mode}"
	[ -n "$mtu_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --mtu ${mtu_value}"
	[ -n "$sndwnd_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --sndwnd ${sndwnd_value}"
	[ -n "$rcvwnd_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --rcvwnd ${rcvwnd_value}"
	[ -n "$nocomp" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --nocomp"
	[ -n "$datashard_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --datashard ${datashard_value}"
	[ -n "$parityshard_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --parityshard ${parityshard_value}"
	[ -n "$dscp_value" ] && KCPTUN_SERVER_ARGS="${KCPTUN_SERVER_ARGS} --dscp ${dscp_value}"

	echo
	echo "配置设置完成, 按任意键继续...或者 Ctrl+C 取消"
	click_to_continue
}

# Pre-installation settings
function pre_install(){
	# Install necessary dependencies
	if [ "$OS" == 'CentOS' ]; then
		yum install -y epel-release
		yum --enablerepo=epel install -y curl wget jq python-setuptools
	else
		apt-get -y update
		apt-get -y install curl wget jq python-setuptools
		if [ $? -ne 0 ]; then
			if [ "$OS" == 'Debian' ]; then
				echo "deb http://ftp.debian.org/debian wheezy-backports main contrib non-free" >> /etc/apt/sources.list
			else
				echo "deb http://archive.ubuntu.com/ubuntu vivid main universe" >> /etc/apt/sources.list
			fi
			apt-get -y update
			apt-get -y install curl wget jq python-setuptools
			if [ $? -ne 0 ]; then
				echo "安装依耐软件包失败！"
				exit_shell
			fi
		fi
	fi
	easy_install supervisor
	if [ $? -ne 0 ]; then
		echo "安装 Supervisor 失败！"
		exit_shell
	fi

	[ -f /etc/supervisor/supervisord.conf ] || echo_supervisord_conf > /etc/supervisor/supervisord.conf
	mkdir -p /etc/supervisor/conf.d
	cd $CUR_DIR
}

# Get json contnet
function get_json_content(){
	KCPTUN_CONTENT=`curl -sfk https://api.github.com/repos/xtaci/kcptun/releases/latest`
	VERSION_CONTENT=`curl -sfk https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/kcptun.json`
	if [ -z "$KCPTUN_CONTENT" ]; then
		echo "获取 Kcptun 文件信息失败, 请检查你的网络连接！"
		exit_shell
	fi
	[ -z "$VERSION_CONTENT" ] && VERSION_CONTENT="{}"
}

# Download kcptun file
function download_file(){
	cd $CUR_DIR
	download_url=`echo "$KCPTUN_CONTENT" | jq -r ".assets[] | select(.name | contains(\"$SPRUCE_TYPE\")) | .browser_download_url"`;

	# Download Kcptun file
	if ! wget --no-check-certificate -O kcptun-"$SPRUCE_TYPE".tar.gz "$download_url"; then
		echo "下载 Kcptun 文件失败！"
		exit_shell
	fi
}

# firewall set
function firewall_set(){
	echo "正在设置防火墙..."
	if centosversion 6; then
		/etc/init.d/iptables status > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			iptables -L -n | grep '${kcptunport}' | grep 'ACCEPT' > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${kcptunport} -j ACCEPT
				iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${kcptunport} -j ACCEPT
				/etc/init.d/iptables save
				/etc/init.d/iptables restart
			else
				echo "端口 ${kcptunport} 已设置！"
			fi
		else
			echo "警告: iptables 已关闭或并未安装, 如果有必要, 请手动添加端口 ${kcptunport} 的防火墙规则！"
		fi
	elif centosversion 7; then
		systemctl status firewalld > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			firewall-cmd --permanent --zone=public --add-port=${kcptunport}/tcp
			firewall-cmd --permanent --zone=public --add-port=${kcptunport}/udp
			firewall-cmd --reload
		else
			echo "Firewalld 未启动, 正在尝试启动..."
			systemctl start firewalld
			if [ $? -eq 0 ]; then
				firewall-cmd --permanent --zone=public --add-port=${kcptunport}/tcp
				firewall-cmd --permanent --zone=public --add-port=${kcptunport}/udp
				firewall-cmd --reload
			else
				echo "警告: 尝试启动 Firewalld 失败, 如果有必要, 请手动添加端口 ${kcptunport} 的防火墙规则！"
			fi
		fi
	fi
	echo "防火墙规则设置成功！"
}

# Config kcptun
function config_kcptun(){
	if [ -f /etc/supervisor/supervisord.conf ]; then
		# sed -i 's/^\[include\]$/&\nfiles = \/etc\/supervisor\/conf.d\/\*\.conf/;t;$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf

		if ! grep -q "^files\s*=\s*\/etc\/supervisor\/conf\.d\/\*\.conf$" /etc/supervisor/supervisord.conf; then
			if grep -q "^\[include\]$" /etc/supervisor/superisord.conf; then
				sed -i '/^\[include\]$/a files = \/etc\/supervisor\/conf.d\/\*\.conf' /etc/supervisor/supervisord.conf
			else
				sed -i '$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf
			fi
		fi

		cat > /etc/supervisor/conf.d/kcptun.conf<<-EOF
[program:kcptun]
directory=/usr/share/kcptun
; Config line. See: https://github.com/xtaci/kcptun
command=/usr/share/kcptun/server_${FILE_SUFFIX} ${KCPTUN_SERVER_ARGS}
process_name=%(program_name)s
autostart=true
redirect_stderr=true
stdout_logfile=/var/log/kcptun.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=0
EOF
	else
		echo "未找到 Supervisor 配置文件！"
		exit_shell
	fi
}

# Download init script
downlod_init_script() {
	if [ "$OS" == 'CentOS' ]; then
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/redhat.init"
	else
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/ubuntu.init"
	fi
	if ! wget --no-check-certificate -O /etc/init.d/supervisord "$init_file_url"; then
		echo "下载 Supervisor 自启脚本失败！"
		exit_shell
	fi
	chmod a+x /etc/init.d/supervisord
}

init_service(){
	if [ "$OS" == 'CentOS' ]; then
		chkconfig --add supervisord
		chkconfig supervisord on

		firewall_set
	else
		update-rc.d -f supervisord defaults
	fi

	service supervisord start
	if [ $? -ne 0 ]; then
		echo "启动 Supervisord 失败！"
		exit_shell
	else
		sleep 5
		supervisorctl reload
		supervisorctl restart kcptun

		if [ $? -ne 0 ]; then
			echo "启动 Kcptun Server 失败！"
			exit_shell
		fi
	fi
	cd $CUR_DIR
}

# Install cleanup
function cleanup(){
	cd $CUR_DIR
	rm -f kcptun-"$SPRUCE_TYPE".tar.gz
	rm -f /usr/share/kcptun/client_"$FILE_SUFFIX"
}

function show_config_info(){
	local kcptun_client_args="-r \"${IP}:${kcptunport}\" -l \":8388\""
	[ -n "$kcptunpwd" ] && kcptun_client_args="${kcptun_client_args} --key \"${kcptunpwd}\""
	[ -n "$crypt_methods" ] && kcptun_client_args="${kcptun_client_args} --crypt ${crypt_methods}"
	[ -n "$comm_mode" ] && kcptun_client_args="${kcptun_client_args} --mode ${comm_mode}"
	[ -n "$nocomp" ] && kcptun_client_args="${kcptun_client_args} --nocomp"
	[ -n "$datashard_value" ] && kcptun_client_args="${kcptun_client_args} --datashard ${datashard_value}"
	[ -n "$parityshard_value" ] && kcptun_client_args="${kcptun_client_args} --parityshard ${parityshard_value}"
	[ -n "$dscp_value" ] && kcptun_client_args="${kcptun_client_args} --dscp ${dscp_value}"

	echo -e "服务器IP: \033[41;37m ${IP} \033[0m"
	echo -e "端口: \033[41;37m ${kcptunport} \033[0m"
	echo -e "加速地址: ${forwardip}:${forwardport}"
	[ -n "$kcptunpwd" ] && echo -e "密码: \033[41;37m ${kcptunpwd} \033[0m"
	[ -n "$crypt_methods" ] && echo -e "加密方式 Crypt: \033[41;37m ${crypt_methods} \033[0m"
	[ -n "$comm_mode" ] && echo -e "加速模式 Mode: \033[41;37m ${comm_mode} \033[0m"
	[ -n "$mtu_value" ] && echo -e "MTU: \033[41;37m ${mtu_value} \033[0m"
	[ -n "$sndwnd_value" ] && echo -e "发送窗口大小 Sndwnd: \033[41;37m ${sndwnd_value} \033[0m"
	[ -n "$rcvwnd_value" ] && echo -e "接受窗口大小 Rcvwnd: \033[41;37m ${rcvwnd_value} \033[0m"
	[ -n "$nocomp" ] && echo -e "数据压缩: \033[41;37m 已禁用 \033[0m"
	[ -n "$datashard_value" ] && echo -e "前向纠错 Datashard: \033[41;37m ${datashard_value} \033[0m"
	[ -n "$parityshard_value" ] && echo -e "前向纠错 Parityshard: \033[41;37m ${parityshard_value} \033[0m"
	[ -n "$dscp_value" ] && echo -e "差分服务代码点 DSCP: \033[41;37m ${dscp_value} \033[0m"
	echo
	echo "推荐的客户端参数为: "
	echo -e "\033[41;37m ${kcptun_client_args} \033[0m"
	echo
	echo "其他参数请自行计算或设置, 详细信息可以查看: https://github.com/xtaci/kcptun"
	echo
	echo -e "Kcptun 目录: \033[41;37m /usr/share/kcptun \033[0m"
	echo -e "Kcptun 日志文件: \033[41;37m /var/log/kcptun.log \033[0m"
	echo
	echo "Supervisor 的相关命令有: service supervisord {start|stop|restart|status}"
	echo "kcptun Server 的相关命令有: supervisorctl {start|stop|restart|status} kcptun"
	echo "已将 Supervisor 加入开机自启, Kcptun Server 会随 Supervisor 的启动而启动"
	echo
	echo -e "如需重新配置服务端, 请使用: \033[41;37m ${0} reconfig \033[0m"
	echo -e "更新服务端, 请使用: \033[41;37m ${0} update \033[0m"
	echo -e "卸载服务端, 请使用: \033[41;37m ${0} uninstall \033[0m"
	echo
	echo "欢迎访问扩软博客: https://blog.kuoruan.com/"
	echo
	echo "我们的QQ群: 43391448"
	echo
	echo "尽情使用吧！"
	echo
}

# Install Kcptun
function install_kcptun(){
	checkos
	rootness
	disable_selinux
	check_install
	set_config
	pre_install
	get_json_content
	get_machine_type
	download_file
	config_kcptun
	# make dir
	mkdir -p /usr/share/kcptun/
	tar -zxf kcptun-"$SPRUCE_TYPE".tar.gz -C /usr/share/kcptun/

	server_file=/usr/share/kcptun/server_"$FILE_SUFFIX"
	if [ -f "$server_file" ]; then
		chmod a+x "$server_file"
		downlod_init_script && init_service

		clear
		echo
		echo "恭喜, Kcptun Server 安装成功！"
		show_config_info
	else
		exit_shell
	fi
	cleanup
}

function check_update(){
	rootness
	echo "开始检查更新..."
	get_json_content
	get_machine_type
	local shell_path=$0
	local new_shell_version=`echo "$VERSION_CONTENT" | jq -r ".shell_version" | grep -oE "[0-9]+"`
	[ -z "$new_shell_version" ] && new_shell_version=0
	if [ "$new_shell_version" -gt "$SHELL_VERSION" ]; then
		local change_log=`echo "$VERSION_CONTENT" | jq -r ".change_log"`
		echo "发现安装脚本更新 (版本号: ${new_shell_version})"
		echo -e "更新说明: \n${change_log}"
		echo
		echo "按任意键开始更新, 或者 Ctrl+C 取消"
		click_to_continue
		echo "正在更新安装脚本..."
		local new_shell_url=`echo "$VERSION_CONTENT" | jq -r ".shell_url"`
		mv -f $shell_path "$shell_path".bak

		if ! wget --no-check-certificate -O "$shell_path" "$new_shell_url"; then
			mv -f "$shell_path".bak $shell_path
			echo "更新安装脚本失败..."
		else
			chmod a+x "$shell_path"
			sed -ri "s/CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
			sed -ri "s/INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
			rm -f "$shell_path".bak
			clear
			echo
			echo "安装脚本已更新到 v${new_init_version}, 正在运行新的脚本..."
			echo

			$shell_path update
			exit 0
		fi
	else
		echo "未发现安装脚本更新..."
	fi

	local kcptun_server=/usr/share/kcptun/server_"$FILE_SUFFIX"
	if [ -f $kcptun_server ]; then
		chmod a+x "$kcptun_server"
		local local_kcptun_version=`$kcptun_server --version | grep -oE "[0-9]+"`
		local remote_kcptun_version=`echo "$KCPTUN_CONTENT" | jq -r ".tag_name" | grep -oE "[0-9]+"`
		[ -z "$remote_kcptun_version" ] && remote_kcptun_version=0
		if [ "$remote_kcptun_version" -gt "$local_kcptun_version" ]; then
			local kcptun_version_desc=`echo "$KCPTUN_CONTENT" | jq -r ".name"`
			echo "发现 Kcptun 新版本 (v${remote_kcptun_version})"
			echo -e "更新说明: \n${kcptun_version_desc}"
			echo
			echo "按任意键开始更新, 或者 Ctrl+C 取消"
			click_to_continue
			echo "正在自动更新 Kcptun..."
			download_file
			tar -zxf kcptun-"$SPRUCE_TYPE".tar.gz -C /usr/share/kcptun
			if [ -f $kcptun_server ]; then
				chmod a+x "$kcptun_server"
				supervisorctl restart kcptun
				cleanup
				echo
				echo "Kcptun Server 已更新到 v${remote_kcptun_version}, 请手动更新客户端！"
				echo
			fi
		else
			echo "未发现 Kcptun 更新..."
		fi
	else
		echo "未找到已安装的 Kcptun Server 执行文件, 或许你并没有安装 Kcptun?"
	fi

	local new_config_version=`echo "$VERSION_CONTENT" | jq -r ".config_version" | grep -oE "[0-9]+"`
	[ -z "$new_config_version" ] && new_config_version=0
	if [ "$new_config_version" -gt "$CONFIG_VERSION" ]; then
		local config_change_log=`echo "$VERSION_CONTENT" | jq -r ".config_change_log"`
		echo "发现 Kcptun 配置更新 (版本号: ${new_config_version}), 需要重新设置 Kcptun..."
		echo -e "更新说明: \n${config_change_log}"
		echo
		echo "按任意键开始配置, 或者 Ctrl+C 取消"
		click_to_continue
		reconfig_kcptun
		sed -i "s/CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" "$shell_path"
	else
		echo "未发现 Kcptun 配置更新..."
	fi

	local new_init_version=`echo "$VERSION_CONTENT" | jq -r ".init_version" | grep -oE "[0-9]+"`
	[ -z "$new_init_version" ] && new_init_version=0
	if [ "$new_init_version" -gt "$INIT_VERSION" ]; then
		local init_change_log=`echo "$VERSION_CONTENT" | jq -r ".init_change_log"`
		echo "发现服务启动脚本文件更新 (版本号: ${new_init_version})"
		echo -e "更新说明: \n${init_change_log}"
		echo
		echo "按任意键开始更新, 或者 Ctrl+C 取消"
		click_to_continue
		echo "正在自动更新启动脚本..."
		checkos
		downlod_init_script
		if centosversion 7; then
			systemctl daemon-reload
		fi
		sed -i "s/INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" "$shell_path"
		echo
		echo "服务启动脚本已更新到 v${new_init_version}, 可能需要重启服务器才能生效！"
		echo
	else
		echo "未发现服务启动脚本更新..."
	fi
}

function uninstall_kcptun(){
	rootness
	echo "是否卸载 Kcptun Server? 按任意键继续...或者 Ctrl+C 取消"
	click_to_continue
	echo "正在卸载 Kcptun 并取消 Supervisor 的开机启动..."
	supervisorctl stop kcptun
	service supervisord stop
	checkos
	if [ "$OS" == 'CentOS' ]; then
		chkconfig supervisord off
	else
		update-rc.d -f supervisord remove
	fi

	rm -f /etc/supervisor/conf.d/kcptun.conf
	rm -rf /usr/share/kcptun/
	echo "Kcptun Server 卸载完成！欢迎再次使用。"
}

function reconfig_kcptun(){
	rootness
	echo "开始重新配置 Kcptun Server..."
	set_config
	get_machine_type
	echo "正在写入新的配置..."
	config_kcptun

	if [ -f /etc/init.d/supervisord ]; then
		service supervisord restart
		sleep 5
		supervisorctl reload
		supervisorctl restart kcptun
		if [ $? -ne 0 ]; then
			echo "自动重启 Kcptun 失败, 请手动检查！"
		fi
	else
		echo "未找到 Supervisor 服务, 无法重启 Kcptun Server, 请手动检查！"
	fi
	echo "恭喜, Kcptun Server 配置完毕！"
	show_config_info
}

# Initialization step
action=$1
[ -z $1 ] && action=install
case "$action" in
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
	*)
		echo "参数错误！ [${action}]"
		echo "请使用: $0 {install|uninstall|update|reconfig}"
		;;
esac
