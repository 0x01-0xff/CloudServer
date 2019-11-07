#!/bin/bash
# Shadowsocks Auto Install For CentOS 7
# By Huson 2019-07-02

SS_START_PORT="23330"
PORT_AMOUNTS="10"
ENC_METHOD="aes-256-cfb"
TCP_FAST_OPEN="true"
# INSTALL_PKG: libev OR python
INSTALL_PKG="libev"
PASSWORD_BIT="24"
OPEN_BBR="NO"
LISTEN_IPV6="YES"
SAVE_PPWD_FILE="/root/SS-PWD.txt"
# USE: # sh install_sss.sh json /etc/shadowsocks-libev/config.json
ONLY_CREATE_JSON="$1"
ONLY_JSON_FILE_PATH="$2"

# Set Time Zone
#timedatectl set-local-rtc 1
#timedatectl set-timezone Asia/Shanghai
###########################################################
clear
red='\033[0;31m'
yellow='\033[0;33m'
plain='\033[0m'
# Make Sure Run As root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as ${red}root${plain}!" && exit 1

create_json_file() {
# Create Config File
	local conf_file=$1
	local port_number=$SS_START_PORT
	if [ -f "$SAVE_PPWD_FILE" ]; then
		rm -f $SAVE_PPWD_FILE
		touch $SAVE_PPWD_FILE
	fi
	if [ ! -d "$(dirname $conf_file)" ]; then
		echo -e "'${red}$(dirname $conf_file)${plain}' folder not found, create config file ${red}FAILED${plain}"
		return 1
	fi
	if [ -f "$conf_file" ]; then
		rm -f $conf_file
		touch $conf_file
	fi
	echo "{" >> $conf_file
	if [ "$LISTEN_IPV6" = "YES" ]; then
		echo "	\"server\":[\"::0\",\"0.0.0.0\"]," >> $conf_file
	else
		echo "	\"server\":\"0.0.0.0\"," >> $conf_file
	fi
	echo "	\"port_password\":{" >> $conf_file
	echo "--------------------------------------" >> $SAVE_PPWD_FILE
	for ((i=1;i<=${PORT_AMOUNTS};i++)); do
		local port_pwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c ${PASSWORD_BIT})
		if [ "$i" = "$PORT_AMOUNTS" ]; then
			echo "		\"${port_number}\":\"${port_pwd}\"" >> $conf_file
		else
			echo "		\"${port_number}\":\"${port_pwd}\"," >> $conf_file
		fi
		echo "${port_number}:${port_pwd}" >> $SAVE_PPWD_FILE
		let port_number+=1
	done
	echo "--------------------------------------" >> $SAVE_PPWD_FILE
	echo "	}," >> $conf_file
	echo "	\"timeout\":\"600\"," >> $conf_file
	echo "	\"method\":\"${ENC_METHOD}\"," >> $conf_file
	echo "	\"mode\":\"tcp_and_udp\"," >> $conf_file
#	if [ "$LISTEN_IPV6" = "YES" ]; then echo "	\"ipv6_first\":true," >> $conf_file; fi
	echo "	\"fast_open\":${TCP_FAST_OPEN}" >> $conf_file
	echo "}" >> $conf_file
	printf "%-40s %40s\n" "Created json File" "[ OK ]"
}
inset_ss_service() {
# Create And Inset Service
	if [ "$INSTALL_PKG" = "python" ]; then
		SS_SERVICE_NAME="shadowsocks"
		cat > /etc/systemd/system/${SS_SERVICE_NAME}.service << EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
TimeoutStartSec=0
ExecStart=/usr/bin/ssserver -c /etc/shadowsocks.json

[Install]
WantedBy=multi-user.target
EOF
	elif [ "$INSTALL_PKG" = "libev" ]; then
		SS_SERVICE_NAME="shadowsocks-mgr"
		MGR_SOCK_FILE="/var/shadowsocks/ss-manager.sock"
		JSON_CFG_FILE="/etc/shadowsocks-libev/config.json"
		if [ ! -d "$(dirname $MGR_SOCK_FILE)" ]; then mkdir $(dirname $MGR_SOCK_FILE); fi
		cat > /etc/systemd/system/${SS_SERVICE_NAME}.service << EOF
[Unit]
Description=Shadowsocks Manager Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-manager -uv --manager-address ${MGR_SOCK_FILE} --executable /usr/bin/ss-server -c ${JSON_CFG_FILE} start

[Install]
WantedBy=multi-user.target
EOF
	else
		echo -e "Install Type Not Fuond, Shadowsocks Service ${red}NO${plain} Inset."
		return 1
	fi
# Enable Shadowsocks Server
	systemctl enable $SS_SERVICE_NAME
	printf "%-40s %40s\n" "Inset Shadowsocks Service" "[ OK ]"
}
set_firewall() {
# Set Firewall
	local fw_port_bg="$SS_START_PORT"
	let local fw_port_end=${fw_port_bg}+${PORT_AMOUNTS}-1
	local firewall_ports="${fw_port_bg}-${fw_port_end}"
	systemctl status firewalld > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		default_zone=$(firewall-cmd --get-default-zone)
		firewall-cmd --permanent --zone=${default_zone} --add-port=${firewall_ports}/tcp
		firewall-cmd --permanent --zone=${default_zone} --add-port=${firewall_ports}/udp
		firewall-cmd --reload
		printf "%-40s %40s\n" "Set Firewall Ports" "[ OK ]"
	else
		echo -e "[${yellow}Warning:${plain}] Firewall Not Running Or Not Installed."
		return 1
	fi
}

python_ss_install() {
# Shadowsocks 2.8.2
	yum install python-pip
	pip install --upgrade pip
	pip install shadowsocks -i https://pypi.python.org/simple
	create_json_file /etc/shadowsocks.json
	inset_ss_service
}
libev_ss_install() {
# Shadowsocks-libev 3.2.0
	wget -P /etc/yum.repos.d https://copr.fedorainfracloud.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo
	yum install epel-release -y
	yum update
	yum install shadowsocks-libev -y
#	rpm --import https://copr-be.cloud.fedoraproject.org/results/librehat/shadowsocks/pubkey.gpg
#	yum install mbedtls-2.7.10-1.el7.x86_64.rpm c-ares-1.10.0-3.el7.x86_64.rpm libev-4.15-7.el7.x86_64.rpm libsodium-1.0.17-1.el7.x86_64.rpm shadowsocks-libev-3.2.0-2.el7.x86_64.rpm -y
	create_json_file /etc/shadowsocks-libev/config.json
	inset_ss_service
}
new_libev_ss_build() { ##### THIS IS NOT FINISH ! DON'T USE IT. #####
# Shadowsocks-libev 3.3.0
# Config File: /etc/shadowsocks-libev/config.json [/etc/sysconfig/shadowsocks-libev: CONFFILE="/etc/shadowsocks-libev/config.json"]
	INSTALL_PKG="libev"
	yum install epel-release -y
	yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel -y
	git clone https://github.com/shadowsocks/shadowsocks-libev.git
	cd shadowsocks-libev
	git submodule update --init --recursive
#	wget https://github.com/shadowsocks/shadowsocks-libev/releases/download/v3.3.0/shadowsocks-libev-3.3.0.tar.gz
#	tar -zxf shadowsocks-libev-3.3.0.tar.gz -C /usr/local
	create_json_file /etc/shadowsocks-libev/config.json


# Git Source
git clone https://github.com/shadowsocks/shadowsocks-libev.git
cd shadowsocks-libev
git submodule update --init --recursive
yum install gettext gcc autoconf libtool automake make asciidoc xmlto c-ares-devel libev-devel
# Installation of Libsodium
export LIBSODIUM_VER=1.0.13
wget https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VER.tar.gz
tar xvf libsodium-$LIBSODIUM_VER.tar.gz
pushd libsodium-$LIBSODIUM_VER
./configure --prefix=/usr && make
make install
popd
ldconfig
# Installation of MbedTLS
export MBEDTLS_VER=2.6.0
wget https://tls.mbed.org/download/mbedtls-$MBEDTLS_VER-gpl.tgz
tar xvf mbedtls-$MBEDTLS_VER-gpl.tgz
pushd mbedtls-$MBEDTLS_VER
make SHARED=1 CFLAGS=-fPIC
make DESTDIR=/usr install
popd
ldconfig
# Start building
./autogen.sh && ./configure && make
make install
#ss-server -c /etc/shadowsocks.json
}
bbr_install() { # PING PROBLEM, NOT TEST.
	rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
	rpm -Uvh https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
#	yum --disablerepo="*" --enablerepo="elrepo-kernel" list available # get kernel list
	yum --enablerepo=elrepo-kernel install kernel-ml kernel-ml-devel -y
#	awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg # check kernel list order
#	vim /etc/default/grub # GRUB_DEFAULT=0 (the 5.0.5 kernel place: 0,1,2,3,4)
	grub2-set-default 0
	grub2-mkconfig -o /boot/grub2/grub.cfg
#	uname -r
	sed -i '/net\.core\.default_qdisc/d' /etc/sysctl.conf > /dev/null 2>&1
	sed -i '/net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf > /dev/null 2>&1
	echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
	echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
	sysctl -p
#	lsmod | grep bbr
#	mount -o remount rw / # for GCP only read
	printf "%-40s %40s\n" "Enable BBR" "[ OK ]"
}
tcp_fast_open() {
# Tcp fastopen
	echo "3" > /proc/sys/net/ipv4/tcp_fastopen
	sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf > /dev/null 2>&1
	echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
	sysctl -p
	printf "%-40s %40s\n" "Tcp Fast Open" "[ OK ]"
}
###########################################################

if [ "$ONLY_CREATE_JSON" = "json" ]; then
	create_json_file $ONLY_JSON_FILE_PATH
	echo ""
	echo -e "# Pleas ${red}COPY${plain} Those ${yellow}PORT${plain} and ${yellow}PASSWORD${plain} OR Save \"${red}${SAVE_PPWD_FILE}${plain}\" #"
	cat $SAVE_PPWD_FILE
	echo ""
	exit 0
fi
if [ "$INSTALL_PKG" = "libev" ]; then libev_ss_install; elif [ "$INSTALL_PKG" = "python" ]; then python_ss_install; fi
if [ "$OPEN_BBR" = "YES" ]; then bbr_install; fi
if [ "$TCP_FAST_OPEN" = "true" ]; then tcp_fast_open; fi
set_firewall

echo ""
echo -e "############ Install ${yellow}${SS_SERVICE_NAME}${plain} DONE! ############"
echo -e "# Pleas ${red}COPY${plain} Those ${yellow}PORT${plain} and ${yellow}PASSWORD${plain} OR Save \"${red}${SAVE_PPWD_FILE}${plain}\" #"
cat $SAVE_PPWD_FILE
echo -e "############ Must be ${red}reboot${plain} the SYSTEM. ############"
echo ""
exit 0

###########################################################
# Server Command shadowsocks or shadowsocks-libev
systemctl enable/disable/start/stop/status -l shadowsocks/shadowsocks-libev
service shadowsocks/shadowsocks-libev start/stop/status
journalctl -u shadowsocks/shadowsocks-mgr
netstat -anut/-lnp
ps aux | grep ss-server
# When change .service
systemctl daemon-reload
# Program Command For python
ssserver -c /etc/shadowsocks.json -d start/stop/restart
# Install
yum install nc rng-tools haveged -y
rngd -r /dev/urandom
nc -Uu /var/shadowsocks/ss-manager.sock


