#!/bin/bash

: <<-'EOF'
Copyright 2016 Xingwang Liao <kuoruan@gmail.com>

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

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

OLD_SHELL_URL='https://github.com/kuoruan/kcptun_installer/raw/master/kcptun_bak.sh'
NEW_SHELL_URL='https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh'
NEW_REPO_URL='https://github.com/kuoruan/shell-scripts'

clear

cat >&2 <<-'EOF'
#########################################################
# Kcptun 服务端一键安装脚本                             #
# 该脚本支持 Kcptun 服务端的安装、更新、卸载及配置      #
# 脚本作者: Index <kuoruan@gmail.com>                   #
# 作者博客: https://blog.kuoruan.com/                   #
# Github: https://github.com/kuoruan/shell-scripts      #
# QQ交流群: 43391448, 68133628                          #
#           633945405                                   #
#########################################################
EOF

# 检查命令是否存在
command_exists() {
	command -v "$@" >/dev/null 2>&1
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

# 安装需要的依赖软件
install_dependence() {
	if command_exists wget; then
		return 0
	fi

	if command_exists yum; then
		(
			set -x
			yum install -y wget ca-certificates
		)

	elif command_exists apt-get; then
		(
			set -x
			apt-get -y update
			apt-get -y install wget ca-certificates
		)
	fi

	set +x
}

do_action() {
	permission_check

	local action=${1:-'install'}
	local id=$2

	cat >&2 <<-EOF
	当前脚本已发布新版本，地址:
	  ${NEW_SHELL_URL}

	旧仓库已废弃，以后所有的脚本都会发布到新仓库:
	  ${NEW_REPO_URL}

	如果你正在使用旧版，可以切换到脚本目录下运行:
	  ./kcptun.sh update
	可以直接升级到新版。

	如果你想继续使用旧版本，请自行下载:
	  ${OLD_SHELL_URL}

	请按任意键自动下载运行新版脚本, 或者 Ctrl + C 退出
	EOF

	any_key_to_continue

	(
		set -x
		sleep 3
	)

	install_dependence

	local shell_name="$0"
	local back_name="${shell_name}.bak"
	(
		set -x
		mv -f "$shell_name" "$back_name"
	)

	if (wget --no-check-certificate -O "$shell_name" "$NEW_SHELL_URL"); then
		(
			set -x
			rm -f "$back_name"
			chmod a+x "$shell_name"
		)
		cat >&2 <<-EOF
		新脚本下载完成，
		三秒后开始执行新脚本...
		EOF

		(
			set -x
			sleep 3
			bash "$shell_name" "$action" "$id"
		)
	else
		(
			set -x
			mv -f "$back_name" "$shell_name"
		)

		cat >&2 <<-EOF
		文件自动下载失败，
		请手动下载运行新脚本:
		  ${NEW_SHELL_URL}
		EOF

		exit 1
	fi
}

do_action "$1" "$2"

exit 0
