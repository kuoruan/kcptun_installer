#!/bin/bash

: <<-'EOF'
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
EOF

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

## 定义常量

SHELL_VERSION=14
CONFIG_VERSION=5
INIT_VERSION=3

CUR_DIR=`pwd` # 当前目录
KCPTUN_INSTALL_DIR=/usr/share/kcptun # kcptun 默认安装目录
KCPTUN_LOG_DIR=/var/log/kcptun # kcptun 日志目录
KCPTUN_RELEASES_URL="https://api.github.com/repos/xtaci/kcptun/releases"
KCPTUN_TAGS_URL="https://github.com/xtaci/kcptun/tags"
SHELL_VERSION_INFO_URL="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/kcptun.json"

## 参数默认值
# associative array
declare -Ar DEFAULT=(
	[LISTEN]=29900
	[TARGET_IP]="127.0.0.1"
	[TARGET_PORT]=12948
	[KEY]="it's a secrect"
	[CRYPT]="aes"
	[MODE]="fast"
	[MTU]=1350
	[SNDWND]=1024
	[RCVWND]=1024
	[DATASHARD]=10
	[PARITYSHARD]=3
	[DSCP]=0
	[NOCOMP]=false
	[NODELAY]=0
	[INTERVAL]=20
	[RESEND]=2
	[NC]=1
	[ACKNODELAY]=false
	[SOCKBUF]=4194304
	[KEEPALIVE]=10
)

declare -ar CRYPTS=(
	"aes"
	"aes-128"
	"aes-192"
	"salsa20"
	"blowfish"
	"twofish"
	"cast5"
	"3des"
	"tea"
	"xtea"
	"xor"
	"none"
)

declare -ar MODES=(
	"normal"
	"fast"
	"fast2"
	"fast3"
	"manual"
)

# 初始化参数
listen_port=${DEFAULT[LISTEN]}
target_ip=${DEFAULT[TARGET_IP]}
target_port=${DEFAULT[TARGET_PORT]}
key=${DEFAULT[KEY]}
crypt=${DEFAULT[CRYPT]}
mode=${DEFAULT[MODE]}
mtu=${DEFAULT[MTU]}
sndwnd=${DEFAULT[SNDWND]}
rcvwnd=${DEFAULT[RCVWND]}
datashard=${DEFAULT[DATASHARD]}
parityshard=${DEFAULT[PARITYSHARD]}
dscp=${DEFAULT[DSCP]}
nocomp=${DEFAULT[NOCOMP]}
nodelay=${DEFAULT[NODELAY]}
interval=${DEFAULT[INTERVAL]}
resend=${DEFAULT[RESEND]}
nc=${DEFAULT[NC]}
acknodelay=${DEFAULT[ACKNODELAY]}
sockbuf=${DEFAULT[SOCKBUF]}
keepalive=${DEFAULT[KEEPALIVE]}

current_count=""

clear

cat >&2 <<-'EOF'
#########################################################
# Kcptun 服务端一键安装脚本                             #
# 该脚本支持 Kcptun 服务端的安装、更新、卸载及配置      #
# 脚本作者: Index <kuoruan@gmail.com>                   #
# 作者博客: https://blog.kuoruan.com/                   #
# Github: https://github.com/kuoruan/kcptun_installer   #
# QQ交流群: 43391448                                    #
#########################################################
EOF

# 检查命令是否存在
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

# 检查变量是否为数字
is_number() {
	expr $1 + 1 >/dev/null 2>&1
}

# 获取实例数量
get_instance_count() {
	ls -l /etc/supervisor/conf.d/ | grep -P "^-.*kcptun[\d]*\.conf" | wc -l
}

# 获取当前配置文件
get_current_config_file() {
	echo "${KCPTUN_INSTALL_DIR}/server-config${current_count}.json"
}

# 获取当前日志文件
get_current_log_file() {
	echo "${KCPTUN_LOG_DIR}/server${current_count}.log"
}

# 获取当前监听端口
get_current_listen_port() {
	local config_file="$(get_current_config_file)"

	if [ -f "$config_file" ]; then
		local listen=$(jq -r ".listen" "$config_file")
		local current_listen_port=$(cut -d ':' -f2 <<< "$listen")

		if [ -n "$current_listen_port" ] && is_number $current_listen_port; then
			echo "$current_listen_port"
		fi
	fi
}

# 检查当前用户是否拥有管理员权限
permission_check() {
	if [ $EUID -ne 0 ]; then
		cat >&2 <<-'EOF'

		权限错误, 请使用 root 用户运行此脚本!
		EOF
		exit 1
	fi
}

# 检查并获取系统信息
linux_check() {
	if $(grep -qi "CentOS" /etc/issue) || $(grep -q "CentOS" /etc/*-release); then
		OS="CentOS"
	elif $(grep -qi "Ubuntu" /etc/issue) || $(grep -q "Ubuntu" /etc/*-release); then
		OS="Ubuntu"
	elif $(grep -qi "Debian" /etc/issue) || $(grep -q "Debian" /etc/*-release); then
		OS="Debian"
	else
		cat >&2 <<-'EOF'

		本脚本仅支持 CentOS 6+, Debian 7+ 或者 Ubuntu 12+, 其他系统请向脚本作者反馈以寻求支持!
		EOF
		exit 1
	fi

	OS_VSRSION=$(grep -oEh "[0-9]+" /etc/*-release | head -n 1) || {
		cat >&2 <<-'EOF'

		无法获取操作系统版本, 请联系脚本作者反馈错误!
		EOF
		exit 1
	}

	if [ "$OS" = "CentOS" -a $OS_VSRSION -lt 6 ]; then
		cat >&2 <<-'EOF'

		暂不支持 CentOS 6 以下版本, 请升级系统或向脚本作者反馈以寻求支持!
		EOF

		exit 1
	fi

	if [ "$OS" = "Ubuntu" -a $OS_VSRSION -lt 12 ]; then
		cat >&2 <<-'EOF'

		暂不支持 Ubuntu 12 以下版本, 请升级系统或向脚本作者反馈以寻求支持!
		EOF
		exit 1
	fi

	if [ "$OS" = "Debian" -a $OS_VSRSION -lt 7 ]; then
		cat >&2 <<-'EOF'

		暂不支持 Debian 7 以下版本, 请升级系统或向脚本作者反馈以寻求支持!
		EOF
		exit 1
	fi
}

# 获取系统位数
get_arch() {
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
get_server_ip() {
	SERVER_IP=$(ip addr | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | \
		grep -Ev "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | \
		head -n 1)
	[ -z "$SERVER_IP" ] && SERVER_IP=$(wget -q -O - ipv4.icanhazip.com)
}

# 禁用 selinux
disable_selinux() {
	if [ -s /etc/selinux/config ] && $(grep -q "SELINUX=enforcing" /etc/selinux/config); then
		sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
		setenforce 0
	fi
}

# 非正常退出
exit_with_error() {
	cat >&2 <<-'EOF'

	Kcptun 服务端安装或配置过程中出现错误!
	希望你能记录下错误信息, 然后将错误信息发送给我
	QQ群: 43391448
	邮箱: kuoruan@gmail.com
	博客: https://blog.kuoruan.com/
	EOF
	exit 1
}

# 任意键继续
any_key_to_continue() {
	SAVEDSTTY=`stty -g`
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2> /dev/null
	stty -raw
	stty echo
	stty $SAVEDSTTY
}

# 检查是否已经安装
installed_check() {
	if [ -s /etc/supervisord.conf ]; then
		cat >&2 <<-EOF

		检测到你曾经通过其他方式安装过 Supervisor , 这会和本脚本安装的 Supervisor 产生冲突
		推荐你备份当前 Supervisor 配置后卸载原有版本
		已安装的 Supervisor 配置文件路径为: /etc/supervisord.conf
		通过本脚本安装的 Supervisor 配置文件路径为: /etc/supervisor/supervisord.conf

		    mv /etc/supervisord.conf /etc/supervisord.conf.bak

		然后你可以尝试通过 $([ "${OS}" = "CentOS" ] && echo -n "yum remove supervisor" || echo -n "apt-get remove supervisor") 来卸载原有版本
		EOF

		exit_with_error
	fi

	if [ -d /etc/supervisor/conf.d/ ]; then
		local instance_count=$(get_instance_count)

		if [ $instance_count -gt 0 ] && [ -d /usr/share/kcptun/ ]; then
			cat >&2 <<-EOF

			检测到你已安装 Kcptun 服务端, 已配置的实例个数为 ${instance_count} 个
			EOF
			while :
			do
				cat >&2 <<-'EOF'

				请选择你希望的操作:
				(1) 覆盖安装
				(2) 重新配置
				(3) 添加实例(多用户)
				(4) 检查更新
				(5) 查看配置
				(6) 查看日志输出
				(7) 自定义版本安装
				(8) 卸载
				(9) 退出
				EOF
				read -p "(默认: 1) 请选择 [1~9]: " sel
				echo
				[ -z "$sel" ] && sel=1

				case $sel in
					1)
						echo "开始覆盖安装 Kcptun 服务端..."
						return 0
						;;
					2)
						select_instance
						reconfig_kcptun
						;;
					3)
						add_instance
						;;
					4)
						check_update
						;;
					5)
						select_instance
						show_instance_config
						;;
					6)
						select_instance
						show_instance_log
						;;
					7)
						manual_install
						;;
					8)
						uninstall_kcptun
						;;
					9)
						;;
					*)
						echo "输入有误, 请输入有效数字 1~9!"
						continue
						;;
				esac

				exit 0
			done
		fi
	fi
}

# 检测端口是否被占用
check_port() {
	[ $# -lt 1 ] && return 1
	local port=$1

	if command_exists netstat; then
		return $(netstat -ntul | grep -qE "[0-9:]:${port}\s")
	elif command_exists ss; then
		return $(ss -ntul | grep -qE "[0-9:]:${port}\s")
	else
		return 1
	fi
}

# 设置 Kcptun 端口
set_listen_port() {
	while :
	do
		cat >&2 <<-'EOF'

		请输入 Kcptun 服务端运行端口 [1~65535]
		EOF
		read -p "(默认: ${DEFAULT[LISTEN]}): " input
		echo
		if [ -n "$input" ]; then
			if is_number $input && [ $input -ge 1 -a $input -le 65535 ]; then
				listen_port="$input"
			else
				echo "输入有误, 请输入 1~65535 之间的数字!"
				continue
			fi
		fi

		current_listen_port=$(get_current_listen_port)
		if check_port $listen_port && [ "$listen_port" != "$current_listen_port" ]; then
			echo "端口已被占用, 请重新输入!"
			continue
		fi

		cat >&2 <<-EOF
		---------------------------
		端口 = ${listen_port}
		---------------------------
		EOF
		break
	done
}

# 禁用 IPv6
set_disable_ipv6() {
	while :
	do
		cat >&2 <<-'EOF'

		是否禁用 IPv6?
		EOF
		read -p "(默认: 不禁用) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					listen_addr=$SERVER_IP
					;;
				n|N)
					unset listen_addr
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		$([ -z "${listen_addr}" ] && echo "不禁用IPv6" || echo "禁用IPv6")
		---------------------------
		EOF
		break
	done
}

# 设置加速的ip地址
set_target_ip() {
	while :
	do
		cat >&2 <<-'EOF'

		请输入需要加速的 IP [0.0.0.0 ~ 255.255.255.255]
		EOF
		read -p "(默认: ${DEFAULT[TARGET_IP]}): " input
		echo
		if [ -n "$input" ]; then
			grep -qE '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$' <<< "$input"
			if [ $? -ne 0 ]; then
				echo "IP 地址格式有误, 请重新输入!"
				continue
			fi

			target_ip="$input"
		fi

		cat >&2 <<-EOF
		---------------------------
		加速 IP = ${target_ip}
		---------------------------
		EOF
		break
	done
}

# 设置加速的端口
set_target_port() {
	while :
	do
		cat >&2 <<-'EOF'

		请输入需要加速的端口 [1~65535]
		EOF
		read -p "(默认: ${DEFAULT[TARGET_PORT]}): " input
		echo
		if [ -n "$input" ]; then
			if is_number $input && [ $input -ge 1 -a $input -le 65535 ]; then
				if [ $input -eq $listen_port ]; then
					echo "加速端口不能和 Kcptun 端口一致!"
					continue
				fi

				target_port=$input
			else
				echo "输入有误, 请输入 1~65535 之间的数字!"
				continue
			fi
		fi

		if [ "$target_ip" = "${DEFAULT[TARGET_IP]}" ]; then
			if ! check_port $target_port; then
				read -p "当前没有软件使用此端口, 确定加速此端口? [y/n]: " yn
				[ -z "$yn" ] && yn="y"
				case ${yn:0:1} in
					y|Y)
						;;
					*)
						continue
						;;
				esac
			fi
		fi

		cat >&2 <<-EOF
		---------------------------
		加速端口 = ${target_port}
		---------------------------
		EOF
		break
	done
}

# 设置 Kcptun 密码
set_key() {
	cat >&2 <<-'EOF'

	请输入 Kcptun 密码
	EOF
	read -p "(默认密码: ${DEFAULT[KEY]}): " input
	echo
	[ -n "$input" ] && key="$input"

	cat >&2 <<-EOF
	---------------------------
	密码 = ${key}
	---------------------------
	EOF
}

# 设置加密方式
set_crypt() {
	while :
	do
		cat >&2 <<-'EOF'

		请选择加密方式(crypt):
		EOF

		for ((i=0; i<${#CRYPTS[@]}; i++)); do
			echo "($(($i + 1))) ${CRYPTS[$i]}"
		done

		read -p "(默认: ${DEFAULT[CRYPT]}) 请选择 [1~$i]: " sel
		echo
		if [ -n "$sel" ]; then
			if is_number $sel && [ $sel -ge 1 -a $sel -le $i ]; then
				crypt=${CRYPTS[$(($sel - 1))]}
			else
				echo "请输入有效数字 1~$i!"
				continue
			fi
		fi

		cat >&2 <<-EOF
		-----------------------------
		加密方式 = ${crypt}
		-----------------------------
		EOF
		break
	done
}

# 设置加速模式
set_mode() {
	while :
	do
		cat >&2 <<-'EOF'

		请选择加速模式(mode):
		EOF

		for ((i=0; i<${#MODES[@]}; i++)); do
			echo "($(($i + 1))) ${MODES[$i]}"
		done

		read -p "(默认: ${DEFAULT[MODE]}) 请选择 [1~$i]: " sel
		echo
		if [ -n "$sel" ]; then
			if is_number $sel && [ $sel -ge 1 -a $sel -le $i ]; then
				mode=${MODES[$(($sel - 1))]}
			else
				echo "请输入有效数字 1~$i!"
				continue
			fi
		fi

		cat >&2 <<-EOF
		---------------------------
		加速模式 = ${mode}
		---------------------------
		EOF
		break
	done

	[ "$mode" = "manual" ] && set_manual_parameters
}

# 设置手动挡参数
set_manual_parameters() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置手动挡参数(预设值或手动设置):
		(1) 策略1: 通过超时重传＋快速重传, 响应速度优先 (最大化响应时间, 适用于网页访问)
		(2) 策略2-1: 仅仅通过超时重传, 带宽效率优先 (有效载比优先, 适用于视频观看)
		(3) 策略2-2: 同上, 与 策略2-1 参数略不相同
		(4) 策略3: 尽可能通过 FEC 纠删, 最大化传输速度 (较为中庸, 兼顾网页和视频)
		(5) 自定义手动挡参数
		EOF
		read -p "(默认: 5) 请选择 [1~5]: " sel
		echo
		[ -z "$sel" ] && sel=5
		case $sel in
			1)
				nodelay=1
				interval=20
				resend=2
				nc=1
				;;
			2)
				nodelay=1
				interval=40
				resend=0
				nc=1
				;;
			3)
				nodelay=0
				interval=20
				resend=0
				nc=1
				;;
			4)
				nodelay=0
				interval=40
				resend=0
				nc=1
				datashard=5
				parityshard=2
				;;
			5)
				set_manual_detail_parameters
				break
				;;
			*)
				echo "请输入有效数字 1~5!"
				continue
				;;
		esac

		cat >&2 <<-EOF
		---------------------------
		nodelay = ${nodelay}
		interval = ${interval}
		resend = ${resend}
		nc = ${nc}
		datashard = ${datashard}
		parityshard = ${parityshard}
		---------------------------
		EOF
		break
	done
}

# 设置手动模式详细参数
set_manual_detail_parameters() {
	cat >&2 <<-'EOF'

	开始配置手动挡参数...
	EOF

	set_nodelay
	set_interval
	set_resend
	set_nc
}

set_nodelay() {
	while :
	do
		cat >&2 <<-'EOF'

		是否启用 nodelay 模式?
		EOF
		read -p "(默认: 不启用) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					nodelay=1
					;;
				n|N)
					nodelay=0
					;;
				*  )
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		nodelay = ${nodelay}
		---------------------------
		EOF
		break
	done
}

set_interval() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置协议内部工作的 interval
		EOF
		read -p "(单位: ms, 默认: ${DEFAULT[INTERVAL]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			interval=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		interval = ${interval}
		---------------------------
		EOF
		break
	done
}

set_resend() {
	while :
	do
		cat >&2 <<-'EOF'

		是否启用快速重传模式(resend)?
		(1) 不启用
		(2) 启用
		(3) 2次ACK跨越重传
		EOF
		read -p "(默认: 3) 请选择 [1~3]: " sel
		echo
		if [ -n "$sel" ]; then
			case $sel in
				1)
					resend=0
					;;
				2)
					resend=1
					;;
				3)
					resend=2
					;;
				*)
					cat >&2 <<-'EOF'

					请输入有效数字 1~3!
					EOF
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		resend = ${resend}
		---------------------------
		EOF
		break
	done
}

set_nc() {
	while :
	do
		cat >&2 <<-'EOF'

		是否关闭流控(nc)?
		EOF
		read -p "(默认: 关闭) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					nc=1
					;;
				n|N)
					nc=0
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		nc = ${nc}
		---------------------------
		EOF
		break
	done
}

set_mtu() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置 UDP 数据包的 MTU (最大传输单元)值
		EOF
		read -p "(默认: ${DEFAULT[MTU]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			mtu=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		MTU = ${mtu}
		---------------------------
		EOF
		break
	done
}

set_sndwnd() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置发送窗口大小(sndwnd)
		EOF
		read -p "(数据包数量, 默认: ${DEFAULT[SNDWND]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			sndwnd=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		sndwnd = ${sndwnd}
		---------------------------
		EOF
		break
	done
}

set_rcvwnd() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置接收窗口大小(rcvwnd)
		EOF
		read -p "(数据包数量, 默认: ${DEFAULT[RCVWND]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			rcvwnd=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		rcvwnd = ${rcvwnd}
		---------------------------
		EOF
		break
	done
}

set_datashard() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置前向纠错 datashard
		EOF
		read -p "(默认: ${DEFAULT[DATASHARD]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			datashard=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		datashard = ${datashard}
		---------------------------
		EOF
		break
	done
}

set_parityshard() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置前向纠错 parityshard
		EOF
		read -p "(默认: ${DEFAULT[PARITYSHARD]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			parityshard=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		parityshard = ${parityshard}
		---------------------------
		EOF
		break
	done
}

set_dscp() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置差分服务代码点(DSCP)
		EOF
		read -p "(默认: ${DEFAULT[DSCP]}): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			dscp=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		DSCP = ${dscp}
		---------------------------
		EOF
		break
	done
}

set_nocomp() {
	while :
	do
		cat >&2 <<-'EOF'

		是否禁用数据压缩?
		EOF
		read -p "(默认: 不禁用) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					nocomp=true
					;;
				n|N)
					nocomp=false
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		nocomp = ${nocomp}
		---------------------------
		EOF
		break
	done
}

# 设置隐藏参数
set_hidden_parameters() {
	cat >&2 <<-'EOF'

	开始配置隐藏参数...
	EOF
	set_acknodelay
	set_sockbuf
	set_keepalive
}

set_acknodelay() {
	while :
	do
		cat >&2 <<-'EOF'

		是否启用 acknodelay 模式?
		EOF
		read -p "(默认: 不启用) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					acknodelay="true"
					;;
				n|N)
					acknodelay="false"
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		cat >&2 <<-EOF
		---------------------------
		acknodelay = ${acknodelay}
		---------------------------
		EOF
		break
	done
}

set_sockbuf() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置 UDP 收发缓冲区大小(sockbuf)
		EOF
		read -p "(单位: MB, 默认: $((${DEFAULT[SOCKBUF]} / 1024 / 1024))): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			sockbuf=$(($input * 1024 * 1024))
		fi

		cat >&2 <<-EOF
		---------------------------
		sockbuf = ${sockbuf}
		---------------------------
		EOF
		break
	done
}

set_keepalive() {
	while :
	do
		cat >&2 <<-'EOF'

		请设置 Keepalive 的间隔时间
		EOF
		read -p "(单位: s, 默认值: ${DEFAULT[KEEPALIVE]}, 前值: 5): " input
		echo
		if [ -n "$input" ]; then
			if ! is_number $input || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			keepalive=$input
		fi

		cat >&2 <<-EOF
		---------------------------
		keepalive = ${keepalive}
		---------------------------
		EOF
		break
	done
}

# 设置参数
set_kcptun_config() {
	echo
	echo "开始配置参数..."

	set_listen_port
	set_disable_ipv6
	set_target_ip
	set_target_port
	set_key
	set_crypt
	set_mode
	set_mtu
	set_sndwnd
	set_rcvwnd
	set_datashard
	set_parityshard
	set_dscp
	set_nocomp

	while :
	do
		cat >&2 <<-'EOF'

		是否调整隐藏参数?
		EOF
		read -p "(默认: 否) [y/n]: " yn
		echo
		if [ -n "$yn" ]; then
			case ${yn:0:1} in
				y|Y)
					set_hidden_parameters
					;;
				n|N)
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	echo "配置完成, 按任意键继续...或者 Ctrl+C 取消"
	any_key_to_continue
}

# 安装需要的依赖软件
install_dependence() {
	cat >&2 <<-'EOF'

	正在安装依赖软件...
	EOF

	if [ "$OS" = "CentOS" ]; then
		yum makecache
		yum --disablerepo=epel update -y ca-certificates || yum update -y ca-certificates
		yum install -y epel-release
		yum --enablerepo=epel install -y curl wget jq python-setuptools tar
	else
		apt-get -y update
		apt-get -y install curl wget jq python-setuptools tar || {

			if [ "$OS" = "Ubuntu" ]; then
				echo "deb http://archive.ubuntu.com/ubuntu vivid main universe" >> /etc/apt/sources.list
			else
				echo "deb http://ftp.debian.org/debian wheezy-backports main contrib non-free" >> /etc/apt/sources.list
			fi

			apt-get -y update
			apt-get -y install curl wget jq python-setuptools tar || {
				cat >&2 <<-'EOF'

				安装依赖软件包失败!
				EOF
				exit_with_error
			}
		}
	fi

	if ! easy_install supervisor; then
		cat >&2 <<-'EOF'

		安装 Supervisor 失败!
		EOF
		exit_with_error
	fi

	[ -d /etc/supervisor/conf.d ] || mkdir -p /etc/supervisor/conf.d

	if [ ! -s /etc/supervisor/supervisord.conf ]; then
		if ! echo_supervisord_conf > /etc/supervisor/supervisord.conf; then
			cat >&2 <<-'EOF'

			创建 Supervisor 配置文件失败!
			EOF
			exit_with_error
		fi
	fi
}

# 通过网络获取需要的信息
get_kcptun_version_info() {
	cat >&2 <<-'EOF'

	正在获取网络信息...
	EOF

	if ! command_exists jq; then
		cat >&2 <<-'EOF'

		jq 命令未安装, 脚本无法正常运行, 请手动安装之后重试.
		EOF
		exit_with_error
	fi

	local request_version=$1
	local kcptun_release_content

	if [ -n "$request_version" ]; then
		kcptun_release_content=$(curl --silent --insecure --fail $KCPTUN_RELEASES_URL | jq -r ".[] | select(.tag_name == \"${request_version}\")")
	else
		kcptun_release_content=$(curl --silent --insecure --fail $KCPTUN_RELEASES_URL | jq -r ".[0]")
	fi

	if [ -n "$kcptun_release_content" ]; then
		kcptun_release_name=$(jq -r ".name" <<< "$kcptun_release_content")
		kcptun_release_tag_name=$(jq -r ".tag_name" <<< "$kcptun_release_content")
		kcptun_release_prerelease=$(jq -r ".prerelease" <<< "$kcptun_release_content")
		kcptun_release_html_url=$(jq -r ".html_url" <<< "$kcptun_release_content")

		kcptun_release_download_url=$(jq -r ".assets[] | select(.name | contains(\"$SPRUCE_TYPE\")) | .browser_download_url" <<< "$kcptun_release_content" | head -n 1) || {
			cat >&2 <<-'EOF'

			获取 Kcptun 下载地址失败, 请重试...
			EOF
			exit_with_error
		}
	else
		if [ -n "$request_version" ]; then
			return 2
		else
			cat >&2 <<-'EOF'

			获取 Kcptun 版本信息失败, 请检查你的网络连接!
			EOF
			exit_with_error
		fi
	fi
}

# 获取shell脚本更新
get_shell_version_info() {
	local shell_version_content=$(curl --silent --insecure --fail $SHELL_VERSION_INFO_URL)
	if [ $? -eq 0 ]; then
		new_shell_version=$(jq -r ".shell_version" <<< "$shell_version_content" | grep -oE "[0-9]+" )
		new_config_version=$(jq -r ".config_version" <<< "$shell_version_content" | grep -oE "[0-9]+" )
		new_init_version=$(jq -r ".init_version" <<< "$shell_version_content" | grep -oE "[0-9]+")

		shell_change_log=$(jq -r ".change_log" <<< "$shell_version_content")
		config_change_log=$(jq -r ".config_change_log" <<< "$shell_version_content")
		init_change_log=$(jq -r ".init_change_log" <<< "$shell_version_content")

		new_shell_url=$(jq -r ".shell_url" <<< "$shell_version_content")
	else
		new_shell_version=0
		new_config_version=0
		new_init_version=0
	fi
}

# 下载文件
download_file(){
	cat >&2 <<-'EOF'

	开始下载文件...
	EOF

	cd "$CUR_DIR"
	if [ `pwd` != "$CUR_DIR" ]; then
		cat >&2 <<-'EOF'

		切换目录失败...
		EOF
		exit_with_error
	fi

	kcptun_file_name="kcptun-${kcptun_release_tag_name}.tar.gz"
	if [ -f "$kcptun_file_name" ] && tar -tf "$kcptun_file_name" &>/dev/null; then
		cat >&2 <<-'EOF'

		已找到 Kcptun 文件压缩包, 跳过下载...
		EOF
		return 0
	fi

	if ! wget --no-check-certificate -c -t 3 -O "$kcptun_file_name" "$kcptun_release_download_url"; then
		cat >&2 <<-EOF

		下载 Kcptun 文件压缩包失败, 你可以尝试手动下载文件:
		1. 下载 ${kcptun_release_download_url}
		2. 将文件重命名为 ${file_name}
		3. 上传文件至脚本当前目录 ${CUR_DIR}
		4. 重新运行脚本开始安装
		EOF
		exit_with_error
	fi

}

# 解压文件
unpack_file() {
	cat >&2 <<-'EOF'

	开始解压文件...
	EOF

	cd "$CUR_DIR"
	[ -d "$KCPTUN_INSTALL_DIR" ] || mkdir -p "$KCPTUN_INSTALL_DIR"
	tar -zxf "$kcptun_file_name" -C "$KCPTUN_INSTALL_DIR"

	local kcptun_server_exec="$KCPTUN_INSTALL_DIR"/server_"$FILE_SUFFIX"
	if [ -f "$kcptun_server_exec" ]; then
		if ! chmod a+x "$kcptun_server_exec"; then
			cat >&2 <<-'EOF'

			无法设置执行权限...
			EOF
			exit_with_error
		fi
	else
		cat >&2 <<-'EOF'

		未在解压文件中找到 Kcptun 服务端执行文件, 请重试!
		EOF
		exit_with_error
	fi
}

# 创建配置文件
config_kcptun() {
	cat >&2 <<-'EOF'

	正在写入配置...
	EOF

	if [ -f /etc/supervisor/supervisord.conf ]; then
		# sed -i 's/^\[include\]$/&\nfiles = \/etc\/supervisor\/conf.d\/\*\.conf/; \
		# t;$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf

		$(grep -q "^files\s*=\s*\/etc\/supervisor\/conf\.d\/\*\.conf$" /etc/supervisor/supervisord.conf) || {
			if grep -q "^\[include\]$" /etc/supervisor/supervisord.conf; then
				sed -i '/^\[include\]$/a files = \/etc\/supervisor\/conf.d\/\*\.conf' /etc/supervisor/supervisord.conf
			else
				sed -i '$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' /etc/supervisor/supervisord.conf
			fi
		}

		# 创建文件夹
		[ -d "$KCPTUN_INSTALL_DIR" ] || mkdir -p "$KCPTUN_INSTALL_DIR"
		[ -d "$KCPTUN_LOG_DIR" ] || mkdir -p "$KCPTUN_LOG_DIR"

		local config_file="$(get_current_config_file)"

		cat > "$config_file"<<-EOF
		{
		    "listen": "${listen_addr}:${listen_port}",
		    "target": "${target_ip}:${target_port}",
		    "key": "${key}",
		    "crypt": "${crypt}",
		    "mode": "${mode}",
		    "mtu": ${mtu},
		    "sndwnd": ${rcvwnd},
		    "rcvwnd": ${sndwnd},
		    "datashard": ${datashard},
		    "parityshard": ${parityshard},
		    "dscp": ${dscp},
		    "nocomp": ${nocomp},
		    "acknodelay": ${acknodelay},
		    "nodelay": ${nodelay},
		    "interval": ${interval},
		    "resend": ${resend},
		    "nc": ${nc},
		    "sockbuf": ${sockbuf},
		    "keepalive": ${keepalive},
		    "log": "$(get_current_log_file)"
		}
		EOF

		cat > "/etc/supervisor/conf.d/kcptun"$current_count".conf"<<-EOF
		[program:kcptun${current_count}]
		directory=${KCPTUN_INSTALL_DIR}
		command=${KCPTUN_INSTALL_DIR}/server_${FILE_SUFFIX} -c "${config_file}"
		process_name=%(program_name)s
		autostart=true
		redirect_stderr=true
		stdout_logfile=$(get_current_log_file)
		stdout_logfile_maxbytes=1MB
		stdout_logfile_backups=0
		EOF
	else
		cat >&2 <<-'EOF'

		未找到 Supervisor 配置文件!
		EOF
		exit_with_error
	fi
}

# 下载服务脚本
downlod_init_script() {
	cat >&2 <<-'EOF'

	开始下载服务脚本...
	EOF

	local init_file_url
	if [ "$OS" = "CentOS" ]; then
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/redhat.init"
	else
		init_file_url="https://raw.githubusercontent.com/kuoruan/kcptun_installer/master/ubuntu.init"
	fi

	if ! wget --no-check-certificate -O /etc/init.d/supervisord "$init_file_url"; then
		cat >&2 <<-'EOF'

		下载 Supervisor init 脚本失败!
		EOF
		exit_with_error
	fi

	if ! chmod a+x /etc/init.d/supervisord; then
		cat >&2 <<-'EOF'

		设置执行权限失败...
		EOF
		exit_with_error
	fi
}

# 安装服务
install_service() {
	cat >&2 <<-'EOF'

	正在配置系统服务...
	EOF

	if [ "$OS" = "CentOS" ]; then
		chkconfig --add supervisord
		chkconfig supervisord on
	else
		update-rc.d -f supervisord defaults
	fi

	restart_supervisor
}

# 设置防火墙
config_firewall() {
	cat >&2 <<-'EOF'

	开始设置防火墙...
	EOF

	if command_exists iptables; then
		if service iptables status >/dev/null 2>&1; then
			if [ -n "$current_listen_port" ]; then
				iptables -D INPUT -p udp --dport ${current_listen_port} -j ACCEPT >/dev/null 2>&1
			fi
			iptables -nL | grep "$listen_port" | grep -q "ACCEPT"
			if [ $? -ne 0 ]; then
				iptables -I INPUT -p udp --dport ${listen_port} -j ACCEPT
				service iptables save
				service iptables restart
			fi

			cat >&2 <<-EOF

			UDP 端口 ${listen_port} 已开放!
			EOF
		else
			cat >&2 <<-EOF

			iptables 未启动或未配置
			如有必要, 请手动添加端口 ${listen_port} 的防火墙规则!
			EOF
		fi
	else
		cat >&2 <<-EOF

		iptables 未安装
		EOF
	fi

	if command_exists firewall-cmd; then
		if systemctl status firewalld >/dev/null 2>&1; then
			if [ -n "$current_listen_port" ]; then
				firewall-cmd --zone=public --remove-port=${current_listen_port}/udp >/dev/null 2>&1
			fi
			firewall-cmd --zone=public --query-port=${listen_port}/udp >/dev/null 2>&1
			if [ $? -ne 0 ]; then
				firewall-cmd --permanent --zone=public --add-port=${listen_port}/udp
				firewall-cmd --reload
			fi
			cat >&2 <<-EOF

			UDP 端口 ${listen_port} 已开放!
			EOF
		else
			cat >&2 <<-EOF

			firewalld 未启动或未配置
			如果有必要, 请手动添加端口 ${listen_port} 的防火墙规则!
			EOF
		fi
	else
		cat >&2 <<-'EOF'

		firewalld 未安装
		EOF
	fi
}

# 安装清理
install_cleanup() {
	cat >&2 <<-'EOF'

	正在清理无用文件...
	EOF

	cd "$CUR_DIR"
	rm -f "$kcptun_file_name"
	rm -f "$KCPTUN_INSTALL_DIR"/client_"$FILE_SUFFIX"
}

# 显示配置信息
show_config_info() {
	echo
	echo -e "服务器IP: \033[41;37m ${SERVER_IP} \033[0m"
	echo -e "端口: \033[41;37m ${listen_port} \033[0m"
	echo -e "加速地址: ${target_ip}:${target_port}"
	[ "$key" != "${DEFAULT[KEY]}" ]                 && echo -e "密码: \033[41;37m ${key} \033[0m"
	[ "$crypt" != "${DEFAULT[CRYPT]}" ]             && echo -e "crypt: \033[41;37m ${crypt} \033[0m"
	[ "$mode" != "${DEFAULT[MODE]}" ]               && echo -e "mode: \033[41;37m ${mode} \033[0m"
	[ "$mtu" != "${DEFAULT[MTU]}" ]                 && echo -e "mtu: \033[41;37m ${mtu} \033[0m"
	[ "$sndwnd" != "${DEFAULT[SNDWND]}" ]           && echo -e "sndwnd: \033[41;37m ${sndwnd} \033[0m"
	[ "$rcvwnd" != "${DEFAULT[RCVWND]}" ]           && echo -e "rcvwnd: \033[41;37m ${rcvwnd} \033[0m"
	[ "$datashard" != "${DEFAULT[DATASHARD]}" ]     && echo -e "datashard: \033[41;37m ${datashard} \033[0m"
	[ "$parityshard" != "${DEFAULT[PARITYSHARD]}" ] && echo -e "parityshard: \033[41;37m ${parityshard} \033[0m"
	[ "$dscp" != "${DEFAULT[DSCP]}" ]               && echo -e "dscp: \033[41;37m ${dscp} \033[0m"
	[ "$nocomp" != "${DEFAULT[NOCOMP]}" ]           && echo -e "nocomp: \033[41;37m ${nocomp} \033[0m"
	[ "$nodelay" != "${DEFAULT[NODELAY]}" ]         && echo -e "nodelay: \033[41;37m ${nodelay} \033[0m"
	[ "$interval" != "${DEFAULT[INTERVAL]}" ]       && echo -e "interval: \033[41;37m ${interval} \033[0m"
	[ "$resend" != "${DEFAULT[RESEND]}" ]           && echo -e "resend: \033[41;37m ${resend} \033[0m"
	[ "$nc" != "${DEFAULT[NC]}" ]                   && echo -e "nc: \033[41;37m ${nc} \033[0m"
	[ "$acknodelay" != "${DEFAULT[ACKNODELAY]}" ]   && echo -e "acknodelay: \033[41;37m ${acknodelay} \033[0m"
	[ "$sockbuf" != "${DEFAULT[SOCKBUF]}" ]         && echo -e "sockbuf: \033[41;37m ${sockbuf} \033[0m"
	[ "$keepalive" != "${DEFAULT[KEEPALIVE]}" ]     && echo -e "keepalive: \033[41;37m ${keepalive} \033[0m"
}

# 处理手机端参数
generate_mobile_args() {
	kcptun_mobile_args="-autoexpire 60"

	[ "$key" != "${DEFAULT[KEY]}" ]                 && kcptun_mobile_args="${kcptun_mobile_args} -key \"${key}\""
	[ "$crypt" != "${DEFAULT[CRYPT]}" ]             && kcptun_mobile_args="${kcptun_mobile_args} -crypt \"${crypt}\""
	[ "$mode" != "${DEFAULT[MODE]}" ]               && kcptun_mobile_args="${kcptun_mobile_args} -mode \"${mode}\""
	[ "$mtu" != "${DEFAULT[MTU]}" ]                 && kcptun_mobile_args="${kcptun_mobile_args} -mtu ${mtu}"
	[ "$datashard" != "${DEFAULT[DATASHARD]}" ]     && kcptun_mobile_args="${kcptun_mobile_args} -datashard ${datashard}"
	[ "$parityshard" != "${DEFAULT[PARITYSHARD]}" ] && kcptun_mobile_args="${kcptun_mobile_args} -parityshard ${parityshard}"
	[ "$dscp" != "${DEFAULT[DSCP]}" ]               && kcptun_mobile_args="${kcptun_mobile_args} -dscp ${dscp}"
	[ "$nocomp" != "${DEFAULT[NOCOMP]}" ]           && kcptun_mobile_args="${kcptun_mobile_args} -nocomp"
	[ "$nodelay" != "${DEFAULT[NODELAY]}" ]         && kcptun_mobile_args="${kcptun_mobile_args} -nodelay ${nodelay}"
	[ "$interval" != "${DEFAULT[INTERVAL]}" ]       && kcptun_mobile_args="${kcptun_mobile_args} -interval ${interval}"
	[ "$resend" != "${DEFAULT[RESEND]}" ]           && kcptun_mobile_args="${kcptun_mobile_args} -resend ${resend}"
	[ "$nc" != "${DEFAULT[NC]}" ]                   && kcptun_mobile_args="${kcptun_mobile_args} -nc ${nc}"
	[ "$acknodelay" != "${DEFAULT[ACKNODELAY]}" ]   && kcptun_mobile_args="${kcptun_mobile_args} -acknodelay"
	[ "$sockbuf" != "${DEFAULT[SOCKBUF]}" ]         && kcptun_mobile_args="${kcptun_mobile_args} -sockbuf ${sockbuf}"
	[ "$keepalive" != "${DEFAULT[KEEPALIVE]}" ]     && kcptun_mobile_args="${kcptun_mobile_args} -keepalive ${keepalive}"
}

show_recommend_config() {
	cat >&2 <<-EOF

	可使用的客户端配置文件为:
	{
	    "localaddr": ":${target_port}",
	    "remoteaddr": "${SERVER_IP}:${listen_port}",
	    "key": "${key}",
	    "crypt": "${crypt}",
	    "mode": "${mode}",
	    "conn": 1,
	    "autoexpire": 60,
	    "mtu": ${mtu},
	    "sndwnd": ${rcvwnd},
	    "rcvwnd": ${sndwnd},
	    "datashard": ${datashard},
	    "parityshard": ${parityshard},
	    "dscp": ${dscp},
	    "nocomp": ${nocomp},
	    "acknodelay": ${acknodelay},
	    "nodelay": ${nodelay},
	    "interval": ${interval},
	    "resend": ${resend},
	    "nc": ${nc},
	    "sockbuf": ${sockbuf},
	    "keepalive": ${keepalive}
	}

	手机端参数可以使用:
	${kcptun_mobile_args}

	各参数详细说明可以查看: https://github.com/xtaci/kcptun
	EOF
}

# 显示安装信息
show_installed_info() {
	show_config_info
	show_installed_version
	show_recommend_config

	cat >&2 <<-EOF

	Kcptun 安装目录: ${KCPTUN_INSTALL_DIR}
	Kcptun 日志目录: ${KCPTUN_LOG_DIR}

	已将 Supervisor 加入开机自启, Kcptun 服务端会随 Supervisor 的启动而启动

	更多使用说明: ${0} help

	欢迎访问扩软博客: https://blog.kuoruan.com/
	我们的QQ群: 43391448

	尽情使用吧!
	EOF
}

# 添加实例
add_instance() {
	permission_check
	linux_check
	get_arch
	get_server_ip

	cat >&2 <<-'EOF'

	你选择了添加实例, 正在开始操作...
	EOF

	current_count=$(($(get_instance_count) + 1))

	set_kcptun_config
	config_kcptun
	config_firewall
	restart_supervisor
	get_installed_version
	generate_mobile_args

	cat >&2 <<-EOF

	恭喜, 实例添加成功!
	EOF

	show_config_info
	show_installed_version
	show_recommend_config
}

# 安装 Kcptun
install_kcptun() {
	permission_check
	linux_check
	installed_check
	disable_selinux
	get_arch
	get_server_ip
	set_kcptun_config
	install_dependence
	get_kcptun_version_info
	download_file
	unpack_file
	config_kcptun
	downlod_init_script
	install_service
	config_firewall
	install_cleanup
	get_installed_version
	generate_mobile_args
	show_installed_info
}

# 重新下载 kcptun
update_kcptun() {
	download_file
	unpack_file

	[ -d "$KCPTUN_LOG_DIR" ] && rm -f "$KCPTUN_LOG_DIR"/* || mkdir -p "$KCPTUN_LOG_DIR"

	restart_supervisor
	install_cleanup
	show_installed_version

	cat >&2 <<-EOF

	恭喜, Kcptun 服务端更新完毕!
	EOF
}

#手动安装
manual_install() {
	permission_check
	linux_check
	get_arch

	cat >&2 <<-'EOF'

	你选择了自定义版本安装, 正在开始操作...
	EOF

	local tag_name=$1
	while :
	do
		if [ -z "$tag_name" ]; then
			cat >&2 <<-'EOF'

			请输入你想安装的 Kcptun 版本的完整 TAG
			EOF
			read -p "(例如: v20160904): " tag_name
			echo
			if $(grep -qE "\w+" <<< "$tag_name"); then

				if [ "$tag_name" = "SNMP_Milestone" ]; then
					echo "不支持此版本, 请重新输入!"
					unset tag_name
					continue
				fi

				local version_num
				version_num=$(grep -oE "[0-9]+" <<< "$tag_name") || version_num=0
				if [ ${#version_num} -eq 8 -a $version_num -le 20160826 ]; then
					echo "暂不支持安装 v20160826 及以前版本"
					continue
				fi
			else
				echo "输入无效, 请重新输入!"
				continue
			fi
		fi

		get_kcptun_version_info $tag_name
		if [ $? -eq 2 ]; then
			cat >&2 <<-EOF
			未找到对应版本下载地址 (TAG: ${tag_name}), 请重新输入!
			你可以前往: ${KCPTUN_TAGS_URL} 查看所有可用 TAG
			EOF
			unset tag_name
			continue
		else
			cat >&2 <<-EOF
			已找到 Kcptun 版本信息, TAG: ${tag_name}
			请按任意键继续安装...
			EOF
			any_key_to_continue
			update_kcptun
			break
		fi
	done
}

# 选择一个实例
select_instance() {
	local instance_count=$(get_instance_count)

	if [ $instance_count -gt 1 ]; then
		cat >&2 <<-'EOF'

		当前有多个实例, 请选择:
		EOF

		for ((i=1; i<=$instance_count; i++)); do
			if [ $i -eq 1 ]; then
				echo "(1) kcptun"
			else
				echo "($i) kcptun$i"
			fi
		done

		while :
		do
			read -p "(默认: 1) 请选择 [1~${instance_count}]: " sel
			if [ -n "$sel" ]; then
				if is_number $sel && [ $sel -ge 1 -a $sel -le $instance_count ]; then
					if [ $sel -ne 1 ]; then
						current_count=$sel
					fi
				else
					cat >&2 <<-EOF

					请输入有效数字 1~${instance_count}!
					EOF
					continue
				fi
			fi
			break
		done
	fi
}

# 加载实例配置信息
load_instance_config() {
	local config_file="$(get_current_config_file)"

	if [ ! -s "$config_file" ]; then
		cat >&2 <<-'EOF'

		实例配置文件不存在或为空, 请检查!
		EOF

		exit_with_error
	fi

	if ! command_exists jq; then
		cat >&2 <<-'EOF'

		jq 命令未安装, 脚本无法正常运行, 请手动安装之后重试.
		EOF
		exit_with_error
	fi

	if ! $(jq -r '.' "$config_file" >/dev/null 2>&1); then
		cat >&2 <<-EOF

		实例配置文件存在错误, 请检查!
		配置文件路径: ${config_file}
		EOF
		exit_with_error
	fi

	local lines=$(jq -r 'to_entries | map("\(.key)=\(.value | @sh)") | .[]' "$config_file")

	while read -r line
	do
		eval "$line"
	done <<< "$lines"

	[ -n "$listen" ] && listen_port=$(cut -d ':' -f2 <<< "$listen")
	if [ -n "$target" ]; then
		target_ip=$(cut -d ':' -f1 <<< "$target")
		target_port=$(cut -d ':' -f2 <<< "$target")
	fi
}

# 显示配置信息
show_instance_config() {
	permission_check
	get_arch
	get_server_ip
	get_installed_version

	cat >&2 <<-'EOF'

	你选择了查看实例配置, 正在读取...
	EOF

	local instance_count=$(get_instance_count)
	if [ -n "$1" ]; then
		if is_number $1 && [ $1 -ge 1 -a $1 -le $instance_count ]; then
			if [ $1 -ne 1 ]; then
				current_count=$1
			fi
		else
			cat >&2 <<-EOF

			参数有误, 请使用 $0 show <id>
			<id> 为实例序号, 当前共有 ${instance_count} 个实例
			EOF

			exit 1
		fi
	fi

	load_instance_config

	if [ -n "$current_count" ]; then
		echo "实例 ${current_count} 的配置信息如下(仅显示非默认值): "
	fi
	get_installed_version
	generate_mobile_args
	show_config_info
	show_installed_version
	show_recommend_config
}

# 显示实例日志
show_instance_log() {
	cat >&2 <<-'EOF'

	你选择了查看实例日志, 正在读取...
	EOF

	local instance_count=$(get_instance_count)

	if [ -n "$1" ]; then
		if is_number $1 && [ $1 -ge 1 -a $1 -le $instance_count ]; then
			if [ $1 -ne 1 ]; then
				current_count=$1
			fi
		else
			cat >&2 <<-EOF

			参数有误, 请使用 $0 log <id>
			<id> 为实例序号, 当前共有 ${instance_count} 个实例
			EOF

			exit 1
		fi
	fi

	local log_file="$(get_current_log_file)"

	if [ -f "$log_file" ]; then
		tail -n 20 -f "$log_file"
	else
		cat >&2 <<-EOF

		未找到所选实例的日志文件...
		EOF

		exit 1
	fi
}

show_installed_version() {
	cat >&2 <<-EOF

	当前安装的 Kcptun 版本为: ${installed_kcptun_version}
	$([ -n "$kcptun_release_html_url" ]  && echo "请前往 ${kcptun_release_html_url} 手动下载客户端文件")
	EOF
}

get_installed_version() {
	cat >&2 <<-'EOF'

	正在获取当前安装的 Kcptun 信息...
	EOF
	local kcptun_server_exec="$KCPTUN_INSTALL_DIR"/server_"$FILE_SUFFIX"
	if [ -x "$kcptun_server_exec" ]; then
		installed_kcptun_version=$(${kcptun_server_exec} -v | awk '{printf $3}')
	else
		unset installed_kcptun_version
		cat >&2 <<-'EOF'

		未找到已安装的 Kcptun 服务端执行文件, 或许你并没有安装 Kcptun?
		请运行脚本来重新安装 Kcptun 服务端
		EOF
		exit_with_error
	fi
}

# 检查更新
check_update() {
	permission_check
	linux_check
	get_arch
	cat >&2 <<-EOF

	你选择了检查更新, 正在开始操作...
	EOF

	local shell_path=$0
	get_shell_version_info

	if [ -n "$new_shell_version" -a $new_shell_version -gt $SHELL_VERSION ]; then
		cat >&2 <<-EOF

		发现一键安装脚本更新, 版本号: ${new_shell_version}
		$(echo -e "更新说明: \n${shell_change_log}")

		按任意键开始更新, 或者 Ctrl+C 取消
		EOF
		any_key_to_continue
		echo "正在更新一键安装脚本..."
		mv -f "$shell_path" "$shell_path".bak

		if wget --no-check-certificate -O "$shell_path" "$new_shell_url"; then
			chmod a+x "$shell_path"
			sed -i -r "s/^CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
			sed -i -r "s/^INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
			rm -f "$shell_path".bak
			clear
			cat >&2 <<-EOF

			安装脚本已更新到 v${new_shell_version}, 正在运行新的脚本...
			EOF

			bash $shell_path update
			exit 0
		else
			mv -f "$shell_path".bak $shell_path

			cat >&2 <<-'EOF'

			下载新的一键安装脚本失败...
			EOF
		fi
	else
		cat >&2 <<-'EOF'

		未发现一键安装脚本更新...
		EOF
	fi

	get_installed_version
	get_kcptun_version_info

	local cur_tag_name="$installed_kcptun_version"

	if [ -n "$cur_tag_name" ] && is_number $cur_tag_name && [ ${#cur_tag_name} -eq 8 ]; then
		cur_tag_name=v"$cur_tag_name"
	fi

	if [ -n "$kcptun_release_tag_name" -a "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
		cat >&2 <<-EOF

		发现 Kcptun 新版本 ${kcptun_release_tag_name}
		$(echo -e "更新说明: \n${kcptun_release_name}")
		$([ "$kcptun_release_prerelease" = "true" ] && echo -e "\033[41;37m 注意: 该版本为预览版, 请谨慎更新 \033[0m")

		按任意键开始更新, 或者 Ctrl+C 取消
		EOF
		any_key_to_continue
		echo "正在自动更新 Kcptun..."
		update_kcptun
	else
		cat >&2 <<-'EOF'

		未发现 Kcptun 更新...
		EOF
	fi

	if [ -n "$new_config_version" -a $new_config_version -gt $CONFIG_VERSION ]; then
		cat >&2 <<-EOF

		发现 Kcptun 配置更新, 版本号: v${new_config_version}, 需要重新设置 Kcptun...
		$(echo -e "更新说明: \n${config_change_log}")

		按任意键开始配置, 或者 Ctrl+C 取消
		EOF
		any_key_to_continue
		reconfig_kcptun
		sed -i "s/^CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" "$shell_path"
	else
		cat >&2 <<-'EOF'

		未发现 Kcptun 配置更新...
		EOF
	fi

	if [ -n "$new_init_version" -a $new_init_version -gt $INIT_VERSION ]; then
		cat >&2 <<-EOF

		发现服务启动脚本文件更新, 版本号: v${new_init_version}
		$(echo -e "更新说明: \n${init_change_log}")

		按任意键开始更新, 或者 Ctrl+C 取消
		EOF
		any_key_to_continue
		echo "正在自动更新启动脚本..."
		downlod_init_script
		[ "$OS" = "CentOS" -a $OS_VSRSION -eq 7 ] && systemctl daemon-reload

		sed -i "s/^INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" "$shell_path"
		cat >&2 <<-EOF

		服务启动脚本已更新到 v${new_init_version}, 可能需要重启服务器才能生效!
		EOF
	else
		cat >&2 <<-'EOF'

		未发现服务启动脚本更新...
		EOF
	fi

	cat >&2 <<-'EOF'

	正在更新 Supervisor...
	EOF

	easy_install -U supervisor >/dev/null 2>&1

	cat >&2 <<-'EOF'

	更新操作已完成!
	EOF
}

# 卸载 Kcptun
uninstall_kcptun() {
	permission_check
	linux_check
	cat >&2 <<-'EOF'

	你选择了卸载 Kcptun 服务端
	按任意键继续...或者 Ctrl+C 取消
	EOF
	any_key_to_continue
	echo "正在卸载 Kcptun 服务端并停止 Supervisor..."
	service supervisord stop

	rm -f "/etc/supervisor/conf.d/kcptun*.conf"
	rm -rf "$KCPTUN_INSTALL_DIR"
	rm -rf "$KCPTUN_LOG_DIR"

	cat >&2 <<-'EOF'

	是否同时卸载 Supervisor ?
	注意: Supervisor 的配置文件将同时被删除
	EOF
	while :
	do
		read -p "(默认: 不卸载) 请选择 [y/n]: " yn
		[ -z "$yn" ] && yn="n"
		case ${yn:0:1} in
			y|Y)
				;;
			n|N)
				break
				;;
			*)
				echo "输入有误, 请重新输入!"
				continue
				;;
		esac

		if [ "$OS" = "CentOS" ]; then
			chkconfig supervisord off
		else
			update-rc.d -f supervisord remove
		fi

		rm -rf "$(easy_install -mxN supervisor | grep 'Using.*supervisor.*\.egg' | awk '{print $2}')"

		rm -f /usr/local/bin/echo_supervisord_conf
		rm -f /usr/local/bin/pidproxy
		rm -f /usr/local/bin/supervisorctl
		rm -f /usr/local/bin/supervisord
		rm -rf /etc/supervisor/
		rm -rf /etc/init.d/supervisord
		break
	done

	cat >&2 <<-'EOF'

	Kcptun 服务端卸载完成, 欢迎再次使用。
	EOF
}

# 重启 Supervisor
restart_supervisor() {
	if [ -x /etc/init.d/supervisord ]; then

		if ! service supervisord restart; then
			cat >&2 <<-'EOF'

			重启 Supervisor 失败, Kcptun 无法正常启动!
			EOF

			exit_with_error
		fi
	else
		cat >&2 <<-'EOF'

		未找到 Supervisor 服务, 请手动检查!
		EOF

		exit_with_error
	fi


}

# 重新配置
reconfig_kcptun() {
	permission_check
	linux_check
	get_server_ip
	get_arch

	cat >&2 <<-'EOF'

	你选择了重新配置实例, 正在开始操作...
	EOF

	if [ -n "$1" ]; then
		local instance_count=$(get_instance_count)

		if is_number $1 && [ $1 -ge 1 -a $1 -le $instance_count ]; then
			if [ $1 -ne 1 ]; then
				current_count=$1
			fi
		else
			cat >&2 <<-EOF

			参数有误, 请使用 $0 reconfig <id>
			<id> 为实例序号, 当前共有 ${instance_count} 个实例
			EOF

			exit 1
		fi
	fi

	while :
	do
		cat >&2 <<-'EOF'

		请选择操作:
		(1) 全部重新配置
		(2) 直接修改配置文件
		EOF
		read -p "(默认: 1) 请选择: " sel
		echo
		if [ -n "$sel" ]; then
			case ${sel:0:1} in
				1)
					;;
				2)
					echo "正在打开配置文件, 请手动修改..."
					local config_file="$(get_current_config_file)"

					if [ -f "$config_file" ]; then
						if command_exists vim; then
							vim "$config_file"
							load_instance_config
							break
						elif command_exists vi; then
							vi "$config_file"
							load_instance_config
							break
						elif command_exists gedit; then
							gedit "$config_file"
							load_instance_config
							break
						else
							echo "未找到可用的编辑器, 正在进入全新配置..."
						fi
					else
						echo "配置文件不存在, 正在进入全新配置..."
					fi
					;;
				*)
					echo "输入有误, 请重新输入!"
					continue
					;;
			esac
		fi

		set_kcptun_config
		config_kcptun
		config_firewall
		break
	done

	[ -d "$KCPTUN_LOG_DIR" ] || mkdir -p "$KCPTUN_LOG_DIR"

	local log_file="$(get_current_log_file)"
	touch "$log_file" && echo > "$log_file"
	restart_supervisor

	cat >&2 <<-'EOF'

	恭喜, Kcptun 服务端配置已更新!
	EOF
	get_installed_version
	generate_mobile_args
	show_config_info
	show_installed_version
	show_recommend_config
}

usage() {
	cat >&2 <<-EOF

	请使用: $0 <option>

	可使用的参数包括 (尖括号为可选):

	    install          安装
	    uninstall        卸载
	    update           检查更新
	    manual           自定义 Kcptun 版本安装
	    help             查看脚本使用说明
	    add              添加一个实例, 多用户使用
	    reconfig <id>    重新配置实例, <id> 为实例序号
	    show <id>        显示实例详细配置, <id> 为实例序号
	    log <id>         显示实例日志, <id> 为实例序号

	Supervisor 命令:
	    service supervisord {start|stop|restart|status}
	                        {启动|关闭|重启|查看状态}
	Kcptun 相关命令:
	    supervisorctl {start|stop|restart|status} kcptun<id>
	                  {启动|关闭|重启|查看状态}
	EOF
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
		reconfig_kcptun $2
		;;
	manual)
		manual_install $2
		;;
	show)
		show_instance_config $2
		;;
	log)
		show_instance_log $2
		;;
	add)
		add_instance
		;;
	help|*)
		usage
		;;
esac

exit 0
