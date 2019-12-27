#!/bin/bash
#
# CentOS 8 Auto Setup First Time
# By Huson 2019-11-05
#
ADD_USER_AND_KEY="YES"
NEW_USER="XXXX"
NEW_USER_PW="xxxxxxxx"
USER_GROUP="root"
RSA_KEY_NAME="gcp-hk-xxx"
USER_HOME="/home/${NEW_USER}"
AUTHORIZED_FILE="${USER_HOME}/.ssh/authorized_keys"
SSH_CFG_FILE="/etc/ssh/sshd_config"
# USE: # sh set_cos8.sh [<-all><-first><-ssh-enable><-key-set><-key-all><-key-only>]
CUR_DIR=$(cd "$(dirname "$0")";pwd)
INSTALL_ACTION="$1"
###########################################################
_red()    { printf '\033[1;31;31m'; printf "$@"; printf '\033[0m'; }
_yellow() { printf '\033[1;31;33m'; printf "$@"; printf '\033[0m'; }
_green()  { printf '\033[1;31;32m'; printf "$@"; printf '\033[0m'; }
[[ $EUID -ne 0 ]] && _red "\nError: This script must be run as root!\n" && exit 1

disable_selinux() {
	_green "Disable SElinux\n"
	#SELINUX=enforcing
	sed -i 's/^\(SELINUX=\).*/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0
}
install_base_packages() {
	_green "Install Packages\n"
	yum install epel-release -y
	yum update -y
	yum install gcc gcc-c++ autoconf libtool automake make gdb cmake git clang clang-analyzer texinfo -y
	yum install vim net-tools nmap psmisc bash-completion lsof dos2unix nc rng-tools tree zip unzip wget curl -y
}
firewall_default() {
	local default_zone
	_green "Set Firewall To Default\n"
	#rm -rf /etc/firewalld/zones/public.xml
	systemctl status firewalld > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		# Add ssh Port
		default_zone=$(firewall-cmd --get-default-zone)
		firewall-cmd --permanent --zone=${default_zone} --add-port=22/tcp
		systemctl stop firewalld
	fi
}
create_user_and_rsakey_file() {
	_green "Adding User: ${NEW_USER}\n"
	if [ "${USER_GROUP}" != "root" ]; then groupadd ${USER_GROUP}; fi
	useradd -g ${USER_GROUP} ${NEW_USER}
	echo ${NEW_USER_PW} | passwd --stdin ${NEW_USER}
	echo "Creating RSA Key: ${RSA_KEY_NAME}, And Import It."
	if [ -f "${CUR_DIR}/${RSA_KEY_NAME}" ]; then rm -f ${CUR_DIR}/${RSA_KEY_NAME}; fi
	if [ -f "${CUR_DIR}/${RSA_KEY_NAME}.pub" ]; then rm -f ${CUR_DIR}/${RSA_KEY_NAME}.pub; fi
	_green "Create Keys: ${RSA_KEY_NAME}\n"
	ssh-keygen -t rsa -C ${NEW_USER} -f ${RSA_KEY_NAME} -N ""
	if [ ! -d "${USER_HOME}/.ssh" ]; then mkdir -p ${USER_HOME}/.ssh; fi
	if [ ! -f "${AUTHORIZED_FILE}" ]; then touch ${AUTHORIZED_FILE}; fi
	echo "import pub key to ${AUTHORIZED_FILE}"
	cat ${CUR_DIR}/${RSA_KEY_NAME}.pub >> ${AUTHORIZED_FILE}
	chown -R ${NEW_USER}:${USER_GROUP} ${USER_HOME}
	chmod 700 -R ${USER_HOME}/.ssh
	chmod 600 ${AUTHORIZED_FILE}
	if [ -f "${USER_HOME}/.ssh/${RSA_KEY_NAME}.pub" ]; then chmod 600 ${USER_HOME}/.ssh/${RSA_KEY_NAME}.pub; fi
	echo "copy keys to ${USER_HOME}"
	cp ${CUR_DIR}/${RSA_KEY_NAME} ${USER_HOME}/${RSA_KEY_NAME}
	cp ${CUR_DIR}/${RSA_KEY_NAME}.pub ${USER_HOME}/${RSA_KEY_NAME}.pub
	chmod +x ${USER_HOME}/${RSA_KEY_NAME} ${USER_HOME}/${RSA_KEY_NAME}.pub
}
echo_key_info() {
	echo "----------------------------------------------------"
	echo "Remember User: $(_yellow "${NEW_USER}"), And The Password"
	_red "DOWNLOAD keys:[${USER_HOME}/${RSA_KEY_NAME} and .pub] To Local!\n"
	echo "RM backup keys: $(_yellow "${CUR_DIR}/${RSA_KEY_NAME}")"
	echo "----------------------------------------------------"
}
enable_ssh() {
	_green "Enable SSH\n"
	sed -i 's/^\(\(#P\)\|P\)ort.*/Port 22/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#L\)\|L\)istenAddress 0\.0\.0\.0/ListenAddress 0\.0\.0\.0/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#L\)\|L\)istenAddress \:\:/\#ListenAddress \:\:/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)ubkeyAuthentication.*/\#PubkeyAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)asswordAuthentication.*/PasswordAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#U\)\|U\)sePAM.*/UsePAM yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)ermitRootLogin.*/PermitRootLogin yes/g' ${SSH_CFG_FILE}
	systemctl restart sshd
}
set_rsa_authentication() {
	_green "Enable RSA KEY Login\n"
	# Enable Key & Password Login
	#sed -i 's/^\(\(#A\)\|A\)uthenticationMethods.*/AuthenticationMethods publickey\,password/g' ${SSH_CFG_FILE}
	# RSA Key Authentication
	sed -i 's/^\(\(#P\)\|P\)ubkeyAuthentication.*/PubkeyAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#A\)\|A\)uthorizedKeysFile.*/AuthorizedKeysFile      \.ssh\/authorized_keys/g' ${SSH_CFG_FILE}
	# Password Login
	sed -i 's/^\(\(#P\)\|P\)asswordAuthentication.*/PasswordAuthentication no/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#U\)\|U\)sePAM.*/UsePAM yes/g' ${SSH_CFG_FILE}
	# Disable "root" Login
	sed -i 's/^\(\(#P\)\|P\)ermitRootLogin.*/PermitRootLogin no/g' ${SSH_CFG_FILE}
	#systemctl restart sshd
	_red "** Will be need RSA KEY to login after reboot! **\n"
}
first_time_set() {
	timedatectl set-local-rtc 1
	timedatectl set-timezone Asia/Shanghai
	install_base_packages
	#disable_selinux
	firewall_default
}
create_and_enable_key() {
	enable_ssh
	create_user_and_rsakey_file
	set_rsa_authentication
	echo_key_info
}

case "${INSTALL_ACTION}" in
	-all) first_time_set && create_and_enable_key;;
	-first) first_time_set;;
	-ssh-enable) enable_ssh;;
	-key-set) set_rsa_authentication;;
	-key-all) create_and_enable_key;;
	-key-only) create_user_and_rsakey_file && echo_key_info;;
	*) _yellow "\nPleas USE: \"# sh set_cos8.sh [<-all><-first><-ssh-enable><-key-set><-key-all><-key-only>]\"\n"; _red 'Done Nothing.\n\n'; exit 1;;
esac

echo ""
echo "DONE!"
echo ""
exit 0
###########################################################

