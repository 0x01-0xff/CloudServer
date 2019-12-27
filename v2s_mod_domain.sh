#!/bin/bash
# Modify Domain Name Of v2ray+caddy [ws+tls+web]
# Make sure your new domain name resolution done
# USE: "# sh v2s_mod_domain.sh xxxx.com"
#

DOMAIN_NAME="$1"
CUR_DIR=$(cd "$(dirname "$0")";pwd)
############################################
V2RAY_BIN_PATH="/usr/bin/v2ray"
V2RAY_CFG_FILE="/etc/v2ray/config.json"
CADDY_BIN_PATH="/usr/local/bin"
CADDY_CFG_PATH="/etc/caddy"
CADDY_CERT_PATH="/etc/ssl/caddy"
CADDY_WWW_PATH="/var/www"
_red()    { printf '\033[1;31;31m'; printf "$@"; printf '\033[0m'; }
_yellow() { printf '\033[1;31;33m'; printf "$@"; printf '\033[0m'; }
_green()  { printf '\033[1;31;32m'; printf "$@"; printf '\033[0m'; }
[[ $EUID -ne 0 ]] && _red "\nError: This script must be run as root!\n" && exit 1
RELEASE_VERSION=`cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'`

set_server_time(){
	_green "Set Server Time\n"
	timedatectl set-local-rtc 1
	timedatectl set-timezone Asia/Shanghai
}
install_base_packages() {
	_green "Install Packages\n"
	yum install epel-release -y
	yum update -y > /dev/null
	#yum install gcc gcc-c++ autoconf libtool automake make gdb cmake git clang clang-analyzer texinfo -y
	yum install vim net-tools nmap psmisc bash-completion lsof dos2unix nc rng-tools tree zip unzip wget curl -y
	yum install lrzsz qrencode libcap -y
}
install_v2ray() {
	_green "Install v2ray\n"
	bash <(curl -L -s https://install.direct/go.sh)
	#./go.sh
	#./go.sh --version v4.20 --local ${CUR_DIR}/v2ray.zip
	#uuid=$(cat /proc/sys/kernel/random/uuid)
	#v2ctl uuid
	create_v2ray_json_cfg ${V2RAY_CFG_FILE}
	echo "test config file"
	${V2RAY_BIN_PATH}/v2ray --test --config ${V2RAY_CFG_FILE}

	systemctl daemon-reload
	systemctl enable v2ray
}
install_caddy() {
	_green "Install Caddy\n"
	#curl https://getcaddy.com | bash -s personal
	wget https://github.com/caddyserver/caddy/releases/download/v1.0.3/caddy_v1.0.3_linux_amd64.tar.gz > /dev/null
	tar -xzf "${CUR_DIR}/caddy_v1.0.3_linux_amd64.tar.gz" -C "${CUR_DIR}/" "caddy"
	tar -xzf "${CUR_DIR}/caddy_v1.0.3_linux_amd64.tar.gz" init/linux-systemd/caddy.service -C "${CUR_DIR}/"
	cp ${CUR_DIR}/init/linux-systemd/caddy.service ${CUR_DIR}/caddy.service
	rm -rf ${CUR_DIR}/init

	cp ${CUR_DIR}/caddy ${CADDY_BIN_PATH}/caddy
	chown root:root ${CADDY_BIN_PATH}/caddy
	chmod 755 ${CADDY_BIN_PATH}/caddy
	setcap 'cap_net_bind_service=+ep' ${CADDY_BIN_PATH}/caddy
	#grep '33' /etc/group
	#usermod -u 36 www-data
	#groupmod -g 36 www-data
	echo "add web user"
	groupadd -g ${WEB_USER_ID} www-data
	useradd -g www-data --no-user-group --home-dir ${CADDY_WWW_PATH} --no-create-home --shell /usr/sbin/nologin --system --uid ${WEB_USER_ID} www-data
	echo "create ${CADDY_CFG_PATH} dir"
	mkdir -p ${CADDY_CFG_PATH}
	chown -R root:root ${CADDY_CFG_PATH}
	create_caddyfile ${CADDY_CFG_PATH}
	echo "create ${CADDY_CERT_PATH} dir"
	mkdir -p ${CADDY_CERT_PATH}
	chown -R root:www-data ${CADDY_CERT_PATH}
	chmod 0770 ${CADDY_CERT_PATH}
	echo "create ROOT:${CADDY_WWW_PATH} dir"
	mkdir -p ${CADDY_WWW_PATH}
	create_error_html 403 ${CADDY_ERR_PATH}
	create_error_html 404 ${CADDY_ERR_PATH}
	cp ${CADDY_ERR_PATH}/403.html ${CADDY_ERR_PATH}/index.html
	cp ${CADDY_ERR_PATH}/403.html ${CADDY_WWW_PATH}/index.html
	chown www-data:www-data ${CADDY_WWW_PATH}
	chmod 555 ${CADDY_WWW_PATH}
	echo "inset caddy service"
	cp ${CUR_DIR}/caddy.service /etc/systemd/system/caddy.service
	if [[ $RELEASE_VERSION -lt 8 ]]; then
		_yellow "CentOS $RELEASE_VERSION detected, fix \"caddy.service\" file\n"
		sed -i 's/^ReadWritePaths=\/etc\/ssl\/caddy/ReadWriteDirectories=\/etc\/ssl\/caddy/g' /etc/systemd/system/caddy.service
	fi
	chmod 644 /etc/systemd/system/caddy.service

	systemctl daemon-reload
	systemctl enable caddy
}
create_caddyfile() {
	local cfg_path="$1"
	echo "create ${cfg_path}/Caddyfile"
	cat > ${cfg_path}/Caddyfile <<-EOF
		${DOMAIN_NAME}
		{
			root ${CADDY_WWW_PATH}
			gzip
			timeouts none
			proxy /${SECURE_PATH} 127.0.0.1:${V2RAY_LISTEN_PORT} {
				websocket
				header_upstream -Origin
			}
			errors {
				400 ${CADDY_ERR_PATH}/404.html
				403 ${CADDY_ERR_PATH}/403.html
				404 ${CADDY_ERR_PATH}/404.html
				* ${CADDY_ERR_PATH}/404.html
			}
		}
	EOF
	chown root:root ${cfg_path}/Caddyfile
	chmod 644 ${cfg_path}/Caddyfile
}
create_error_html() {
	local error_code="$1"
	local error_html_path="$2"
	local htm_title htm_contents
	echo "create ${error_code}.html to ${error_html_path}"
	if [[ ! -d ${error_html_path} ]]; then mkdir -p ${error_html_path}; fi
	if [[ "${error_code}" = "403" ]]; then
		htm_title="403 Forbidden"
		htm_contents="Sorry, you don't have permission to access on this server."
	elif [[ "${error_code}" = "404" ]]; then
		htm_title="404 Not Found"
		htm_contents="Sorry, the requested URL was not found on this server."
	else
		echo "ERROR CODE NOT FOUND."
		return 1
	fi
	cat > ${error_html_path}/${error_code}.html <<-EOF
		<!DOCTYPE html>
		<html>
		<head>
		<title>${htm_title}</title>
		<style>
		body {font-family: Tahoma, Verdana, Arial, sans-serif;}
		</style>
		</head>
		<body>
		<h1>${htm_title}</h1>
		<hr>
		<p>${htm_contents}</p>
		<p><em>nginx/1.16.1</em></p>
		</body>
		</html>
	EOF
}
create_v2ray_json_cfg() {
local _cfg_file="$1"
echo "create ${_cfg_file}\n"
cat > ${_cfg_file} <<-EOF
{
	"log": {
		"access": "/var/log/v2ray/access.log",
		"error": "/var/log/v2ray/error.log",
		"loglevel": "warning"
	},
	"inbounds": [
		{
			"port": ${V2RAY_LISTEN_PORT},
			"listen": "127.0.0.1",
			"protocol": "vmess",
			"settings": {
				"clients": [
					$(v2ray_uuid_mkadd ${UUID_USERS})
				]
			},
			"streamSettings": {
				"network": "ws",
				"wsSettings": {
					"path": "/${SECURE_PATH}"
				}
			}
		}
	],
	"outbounds": [
		{
			"protocol": "freedom",
			"settings": {}
		},
		{
			"protocol": "blackhole",
			"settings": {},
			"tag": "blocked"
		}
	],
	"routing": {
		"rules": [
			{
				"type": "field",
				"ip": ["geoip:private"],
				"outboundTag": "blocked"
			},
			{
				"type": "field",
				"protocol": ["bittorrent"],
				"outboundTag": "blocked"
			}
		]
	}
}
EOF
}
v2ray_uuid_mkadd() {
	local uid_num=$1
	local end_symbol=","
	local i tmp_uuid
	for ((i=1;i<=$uid_num;i++)); do
		tmp_uuid="$(cat /proc/sys/kernel/random/uuid)"
		if [[ ${i} = ${uid_num} ]]; then end_symbol=""; fi
		echo "					{ // UUID ${i}/${uid_num}"
		echo "						\"id\": \"${tmp_uuid}\","
		echo "						\"level\": 1,"
		echo "						\"alterId\": 64"
		echo "					}${end_symbol}"
		echo "UUID ${i}/${uid_num}: ${tmp_uuid}" >> ${SAVE_CONFIG_FILE}
	done
}
inset_firewall() {
	_green "Inset Firewall Rules\n"
	local default_zone
	systemctl status firewalld > /dev/null 2>&1
	if [[ $? -eq 0 ]]; then
		default_zone=$(firewall-cmd --get-default-zone)
		firewall-cmd --permanent --zone=${default_zone} --add-service=http
		firewall-cmd --permanent --zone=${default_zone} --add-service=https
		firewall-cmd --reload
		echo "Set Firewall Ports OK"
	else
		_yellow "Warning: Firewall Not Running Or Not Installed."
	fi
}
install_v2ray_caddy(){
	if [ -f "${SAVE_CONFIG_FILE}" ]; then rm -f ${SAVE_CONFIG_FILE}; fi
	touch ${SAVE_CONFIG_FILE}
	echo "Domain: ${DOMAIN_NAME}" >> ${SAVE_CONFIG_FILE}
	echo "Path: /${SECURE_PATH}" >> ${SAVE_CONFIG_FILE}
	install_v2ray
	install_caddy
	inset_firewall
	#systemctl start caddy
	#systemctl start v2ray
	_red "\nCopy this:\n"
	_yellow "$(cat ${SAVE_CONFIG_FILE})\n\n"
	_yellow "Config save at: \"${SAVE_CONFIG_FILE}\"\n\n"
}
###########################################

case "${INSTALL_ACTION}" in
	time) set_server_time;;
	pkg) install_base_packages;;
	v2s) install_v2ray_caddy;;
	*) _yellow '\nPleas USE: "# sh install_v2s.sh time/pkg/v2s"\n'; _red 'Done Nothing.\n\n'; exit 1;;
esac

_green "DONE.\n"
exit 0
###########################################

