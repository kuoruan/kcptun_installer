#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

SHELL_VERSION=1
CONFIG_VERSION=1

clear
echo
echo "#############################################################"
echo "# Kcptun Server 一键安装脚本                                #"
echo "# 该脚本支持 Kcptun Server 的安装、更新及卸载               #"
echo "# 介绍: https://blog.kuoruan.com/102.html                   #"
echo "# 作者: Index <kuoruan@gmail.com>                           #"
echo "# 致谢: 本脚本编写过程中参考了 @teddysun 的SS一键安装脚本    #"
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
		echo "错误, 请使用 root 用户运行此脚本！"
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
	local code=$1
	local version="`get_osversion`"
	local main_ver=${version%%.*}
	if [ $main_ver == $code ]; then
		return 0
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
	if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
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

# Pre-installation settings
function pre_install(){
	# Not support CentOS 5
	if centosversion 5; then
		echo "暂不支持 CentOS5, 请重装系统为 CentOS 6+, Debian 7+ 或者 Ubuntu 12+ 并重试!"
		exit_shell
	fi
	# Set Kcptun config port
	while true
	do
		echo -e "请输入 Kcptun Server 端口 [1-65535]:"
		read -p "(默认: 554):" kcptunport
		[ -z "$kcptunport" ] && kcptunport="554"
		expr $kcptunport + 0 &>/dev/null
		if [ $? -eq 0 ]; then
			if [ $kcptunport -ge 1 ] && [ $kcptunport -le 65535 ]; then
				port_stat=`netstat -an | egrep "[0-9]:${kcptunport} .+LISTEN"`
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
		echo -e "请输入需要加速的端口 [1-65535]:"
		read -p "(默认: 8388):" forwardport
		[ -z "$forwardport" ] && forwardport="8388"
		expr $forwardport + 0 &>/dev/null
		if [ $? -eq 0 ]; then
			if [ $forwardport -ge 1 ] && [ $forwardport -le 65535 ]; then
				port_stat=`netstat -an | egrep "[0-9]:${forwardport} .+LISTEN"`
				if [ -z "$port_stat" ]; then
					read -p "似乎并没有软件使用此端口, 确定继续使用此端口?(y/n)" yn
					case ${yn:0:1} in
						y|Y ) ;;
						* ) continue;;
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
	echo "请输入 Kcptun Server 密码:"
	read -p "(如果不想使用密码请留空):" kcptunpwd
	echo
	echo "---------------------------"
	if [ -z "$kcptunpwd" ]; then
		echo "密码未设置"
	else
		echo "密码 = $kcptunpwd"
	fi
	echo "---------------------------"
	echo

	get_char(){
		SAVEDSTTY=`stty -g`
		stty -echo
		stty cbreak
		dd if=/dev/tty bs=1 count=1 2> /dev/null
		stty -raw
		stty echo
		stty $SAVEDSTTY
	}
	echo
	echo "按任意键继续安装...或者 Ctrl+C 取消安装"
	char=`get_char`
	# Install necessary dependencies
	if [ "$OS" == 'CentOS' ]; then
		yum install -y epel-release
		yum --enablerepo=epel install -y curl wget jq python-setuptools
		easy_install supervisor
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

	mkdir -p /etc/supervisor/conf.d
	echo_supervisord_conf > /etc/supervisor/supervisord.conf
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
		grep -q "files=\/etc\/supervisor\/conf.d\/\*\.conf" replace.sh || {
			echo -e "[include]\nfiles=/etc/supervisor/conf.d/*.conf" >> /etc/supervisor/supervisord.conf
		}
		cat > /etc/supervisor/conf.d/kcptun.conf<<-EOF
[program:kcptun]
directory=${CUR_DIR}/kcptun
; 如需修改参数, 请修改下面这一行:
command=${CUR_DIR}/kcptun/server_${FILE_SUFFIX} -t "127.0.0.1:${forwardport}" -l ":${kcptunport}" -mode fast2
; 各参数的详细信息请查看: https://github.com/xtaci/kcptun
process_name=%(program_name)s
autostart=true
redirect_stderr=true
stdout_logfile=${CUR_DIR}/kcptun/kcptun.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=0
EOF
	else
		echo "未找到 Supervisor 配置文件！"
		exit_shell
	fi
}

init_service(){
	# Download init script
	if [ "$OS" == 'CentOS' ]; then
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/redhat.init"
	else
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/ubuntu.init"
	fi
	if ! wget --no-check-certificate -O /etc/init.d/supervisord "$init_file_url"; then
		echo "下载 supervisor 自启脚本失败！"
		exit_shell
	fi
	chmod a+x /etc/init.d/supervisord

	if [ "$OS" == 'CentOS' ]; then
		chkconfig --add supervisord
		chkconfig supervisord on

		firewall_set
	else
		update-rc.d -f supervisord defaults
	fi

	service supervisord restart
	sleep 3
	if [ $? -ne 0 ]; then
		echo "启动 Supervisord 失败！"
		exit_shell
	else
		supervisorctl reload
		supervisorctl restart kcptun

		if [ $? -ne 0 ]; then
			echo "启动 Kcptun Server 失败！"
			exit_shell
		fi
	fi
}

# Install cleanup
function cleanup(){
	cd $CUR_DIR
	rm -f kcptun-"$SPRUCE_TYPE".tar.gz
	rm -f "$CUR_DIR"/kcptun/client_"$FILE_SUFFIX"
}

# Install Kcptun
function install_kcptun() {
	checkos
	rootness
	disable_selinux
	pre_install
	get_json_content
	get_machine_type
	download_file
	config_kcptun
	# make dir
	mkdir -p "$CUR_DIR"/kcptun
	tar -zxf kcptun-"$SPRUCE_TYPE".tar.gz -C "$CUR_DIR"/kcptun
	cd "$CUR_DIR"/kcptun
	server_file="$CUR_DIR"/kcptun/server_"$FILE_SUFFIX"
	if [ -f "$server_file" ]; then
		chmod a+x "$server_file"
		init_service

		clear
		echo
		echo "恭喜, Kcptun Server 安装成功！"
		echo -e "服务器IP: \033[41;37m ${IP} \033[0m"
		echo -e "端口: \033[41;37m ${kcptunport} \033[0m"
		if [ -z "$kcptunpwd" ]; then
			echo "未设置密码, 请留空"
		else
			echo -e "密码: \033[41;37m ${kcptunpwd} \033[0m"
		fi
		echo
		echo -e "如需修改配置, 请查看文件 \033[41;37m /etc/supervisor/conf.d/kcptun.conf \033[0m"
		echo
		echo "欢迎访问: https://blog.kuoruan.com/102.html"
		echo
		echo "我们的QQ群: 43391448"
		echo
		echo "尽情使用吧！"
		echo
	else
		exit_shell
	fi
	cleanup
}

function check_update(){
	echo "开始检查更新..."
	get_json_content
	get_machine_type
	local shell_path=$0
	local new_shell_version=`echo "$VERSION_CONTENT" | jq -r ".shell_version" | grep -oE "[0-9]+"`
	[ -z "$new_shell_version" ] && new_shell_version=0
	if [ "$new_shell_version" -gt "$SHELL_VERSION" ]; then
		echo "正在更新脚本文件..."
		local new_shell_url=`echo "$VERSION_CONTENT" | jq -r ".shell_url"`
		mv -f $shell_path "$shell_path".bak

		if ! wget --no-check-certificate -O "$shell_path" "$new_shell_url"; then
			mv -f "$shell_path".bak $shell_path
			echo "更新脚本失败..."
		else
			chmod a+x "$shell_path"
			clear
			echo
			echo "脚本已更新, 正在运行新的脚本..."
			echo

			sed -ri "s/CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "${shell_path}"

			$shell_path update
			exit 0
		fi
	fi

	local kcptun_server="$CUR_DIR"/kcptun/server_"$FILE_SUFFIX"
	if [ -f $kcptun_server ]; then
		chmod a+x "$kcptun_server"
		local local_kcptun_version=`$kcptun_server --version | grep -oE "[0-9]+"`
		local remote_kcptun_version=`echo "$KCPTUN_CONTENT" | jq -r ".tag_name" | grep -oE "[0-9]+"`
		[ -z "$remote_kcptun_version" ] && remote_kcptun_version=0
		if [ "$remote_kcptun_version" -gt "$local_kcptun_version" ]; then
			echo "发现 Kcptun 新版本, 正在自动更新..."
			download_file
			tar -zxf kcptun-"$SPRUCE_TYPE".tar.gz -C "$CUR_DIR"/kcptun
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
		echo "未找到已安装的 Kcptun Server 执行文件, 请将该脚本放到 kcptun 文件夹同级目录！"
	fi

	local new_config_version=`echo "$VERSION_CONTENT" | jq -r ".config_version" | grep -oE "[0-9]+"`
	[ -z "$new_config_version" ] && new_config_version=0
	if [ "$new_config_version" -gt "$CONFIG_VERSION" ]; then
		echo "发现配置文件更新, 正在更新配置文件..."
		config_kcptun
		supervisorctl restart kcptun
		sed -i "s/CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" "${shell_path}"
	fi
}

function uninstall_kcptun(){
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
	rm -rf "$CUR_DIR"/kcptun/
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
	*)
		echo "参数错误！ [${action}]"
		echo "请使用: `basename $0` {install|uninstall|update}"
		;;
esac
