#!/bin/bash
#
# CentOS 7 Auto Setup First Time
# By Huson 2019-10-14

# If $ALIYUN_HOST is "YES", Then Will be Clean Up Ali Software
ALIYUN_HOST="YES"
ADD_USER_AND_KEY="YES"
NEW_USER="XXXX"
NEW_USER_PW="xxxxxxxx"
USER_GROUP="root"
UPDATE_SYSTEM_PKG="NO"
RSA_KEY_NAME="alicloud-hk"
USER_HOME="/home/${NEW_USER}"
AUTHORIZED_FILE="${USER_HOME}/.ssh/authorized_keys"
SSH_CFG_FILE="/etc/ssh/sshd_config"
# USE: # sh set_cos7.sh ssh-key
ONLY_SSH_KEY_AUTH=$1
###########################################################
clear
red='\033[0;31m'
yellow='\033[0;33m'
plain='\033[0m'
# Make Sure Run As root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as ${red}root${plain}!" && exit 1

disable_selinux() {
#SELINUX=enforcing
	sed -i 's/^\(SELINUX=\).*/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0
}
replace_yum_source() {
	echo ""
	echo "Replace yum Source To CentOS 7 Default ..."
	rm -rf /etc/yum.repos.d/
	rpm -Uvh --force http://mirror.centos.org/centos/7.6.1810/os/x86_64/Packages/centos-release-7-6.1810.2.el7.centos.x86_64.rpm --quiet
#	rpm -Uvh --force https://raw.githubusercontent.com/0x01-0xff/CloudSetup/master/CleanUpALI/epel-release/centos-release.rpm --quiet
#	rpm -Uvh --force https://mirror.webtatic.com/yum/el7/webtatic-release.rpm --quiet
	yum clean all
	yum makecache
#	yum repolist
	if [ "$UPDATE_SYSTEM_PKG" = "YES" ]; then yum update -y; fi
#	lsb_release -a
	printf "%-40s %40s\n" "Replace yum Source To CentOS 7 Default" "[ OK ]"
}
install_base_packages() {
	echo ""
	echo "Install Base Packages ..."
	yum update -y > /dev/null 2>&1
	yum install gcc gcc-c++ autoconf libtool automake make gdb cmake git clang clang-analyzer texinfo -y
	yum install vim net-tools nmap psmisc bash-completion lsof dos2unix nc rng-tools ntp ntpdate haveged tree wget curl -y
	printf "%-40s %40s\n" "Install Base Packages" "[ OK ]"
}
firewall_default() {
	echo ""
	echo "Set Firewall To Default ..."
	rm -rf /etc/firewalld/zones/public.xml
	systemctl status firewalld > /dev/null 2>&1
	if [ $? -eq 0 ]; then
# Add ssh Port
		default_zone=$(firewall-cmd --get-default-zone)
		firewall-cmd --permanent --zone=${default_zone} --add-port=22/tcp
		systemctl stop firewalld
	fi
	cat > /etc/firewalld/zones/public.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <description>For use in public areas. You do not trust the other computers on networks to not harm your computer. Only selected incoming connections are accepted.</description>
  <service name="ssh"/>
  <service name="dhcpv6-client"/>
</zone>
EOF
	printf "%-40s %40s\n" "Set Firewall To Default" "[ OK ]"
}
create_user_and_rsakey_file() {
	echo ""
	echo "Adding User: ${NEW_USER}"
	CUR_DIR=`pwd`
	if [ "${USER_GROUP}" != "root" ]; then groupadd ${USER_GROUP}; fi
	useradd -g ${USER_GROUP} ${NEW_USER}
	echo ${NEW_USER_PW} | passwd --stdin ${NEW_USER}
	echo "Creating RSA Key: ${RSA_KEY_NAME}, And Import It."
	if [ -f "${CUR_DIR}/${RSA_KEY_NAME}" ]; then rm -f ${CUR_DIR}/${RSA_KEY_NAME}; fi
	if [ -f "${CUR_DIR}/${RSA_KEY_NAME}.pub" ]; then rm -f ${CUR_DIR}/${RSA_KEY_NAME}.pub; fi
	ssh-keygen -t rsa -C ${NEW_USER} -f ${RSA_KEY_NAME} -N ""
	if [ ! -d "${USER_HOME}/.ssh" ]; then mkdir ${USER_HOME}/.ssh; fi
	if [ ! -f "${AUTHORIZED_FILE}" ]; then touch ${AUTHORIZED_FILE}; fi
	cat ${CUR_DIR}/${RSA_KEY_NAME}.pub >> ${AUTHORIZED_FILE}
	chown -R ${NEW_USER}:${USER_GROUP} ${USER_HOME}
	chmod 700 -R ${USER_HOME}/.ssh
	chmod 600 ${AUTHORIZED_FILE}
	if [ -f "${USER_HOME}/.ssh/${RSA_KEY_NAME}.pub" ]; then chmod 600 ${USER_HOME}/.ssh/${RSA_KEY_NAME}.pub; fi
	cp ${CUR_DIR}/${RSA_KEY_NAME} ${USER_HOME}/${RSA_KEY_NAME}
	cp ${CUR_DIR}/${RSA_KEY_NAME}.pub ${USER_HOME}/${RSA_KEY_NAME}.pub
	chmod +x ${USER_HOME}/${RSA_KEY_NAME} ${USER_HOME}/${RSA_KEY_NAME}.pub
	echo -e "** ${red}get keys:[${USER_HOME}/${RSA_KEY_NAME} and .pub] to local!${plain} **"
	echo -e "** ${red}and rm keys:[root/${RSA_KEY_NAME} and .pub]!${plain} **"
	printf "%-40s %40s\n" "Add User And Create RSA Key" "[ OK ]"
}
enable_ssh() {
# Enable ssh
	sed -i 's/^\(\(#P\)\|P\)ort.*/Port 22/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#L\)\|L\)istenAddress 0\.0\.0\.0/ListenAddress 0\.0\.0\.0/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#L\)\|L\)istenAddress \:\:/\#ListenAddress \:\:/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)ubkeyAuthentication.*/\#PubkeyAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)asswordAuthentication.*/PasswordAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#U\)\|U\)sePAM.*/UsePAM yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#P\)\|P\)ermitRootLogin.*/PermitRootLogin yes/g' ${SSH_CFG_FILE}
	systemctl restart sshd
	printf "%-40s %40s\n" "Enable ssh" "[ OK ]"
}
set_rsa_authentication() {
	echo ""
	echo -e "** ${red}You are setting ssh login by RSA key!${plain} **"
	echo -e "** ${red}After reboot, will need RSA key to login!${plain} **"
# Enable Key & Password Login
#	sed -i 's/^\(\(#A\)\|A\)uthenticationMethods.*/AuthenticationMethods publickey\,password/g' ${SSH_CFG_FILE}
# RSA Key Authentication
	sed -i 's/^\(\(#P\)\|P\)ubkeyAuthentication.*/PubkeyAuthentication yes/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#A\)\|A\)uthorizedKeysFile.*/AuthorizedKeysFile      \.ssh\/authorized_keys/g' ${SSH_CFG_FILE}
# Password Login
	sed -i 's/^\(\(#P\)\|P\)asswordAuthentication.*/PasswordAuthentication no/g' ${SSH_CFG_FILE}
	sed -i 's/^\(\(#U\)\|U\)sePAM.*/UsePAM yes/g' ${SSH_CFG_FILE}
# Disable "root" Login
	sed -i 's/^\(\(#P\)\|P\)ermitRootLogin.*/PermitRootLogin no/g' ${SSH_CFG_FILE}
#	systemctl restart sshd
	printf "%-40s %40s\n" "Set ssh Login By RSA Key" "[ OK ]"
}
##################### Clean Up Aliyun Begin #####################
check_gentoo() {
	local var=$(lsb_release -a | grep Gentoo)
	if [ -z "${var}" ]; then local var=$(cat /etc/issue | grep Gentoo); fi
	if [ -d "/etc/runlevels/default" -a -n "${var}" ]; then LINUX_RELEASE="GENTOO"; else LINUX_RELEASE="OTHER"; fi
}
stop_aegis_quartz() {
	killall -9 aegis_cli > /dev/null 2>&1
	killall -9 aegis_update > /dev/null 2>&1
	killall -9 aegis_cli > /dev/null 2>&1
	killall -9 AliYunDun > /dev/null 2>&1
	killall -9 AliHids > /dev/null 2>&1
	killall -9 AliYunDunUpdate > /dev/null 2>&1
    printf "%-40s %40s\n" "Stop aegis" "[ OK ]"
	killall -9 aegis_quartz > /dev/null 2>&1
	printf "%-40s %40s\n" "Stop quartz" "[ OK ]"
}
uninstall_aegis_service() {
	check_gentoo
	if [ -f "/etc/init.d/aegis" ]; then
		/etc/init.d/aegis stop > /dev/null 2>&1
		rm -f /etc/init.d/aegis
	fi
	if [ "$LINUX_RELEASE" = "GENTOO" ]; then
		rc-update del aegis default 2> /dev/null
		if [ -f "/etc/runlevels/default/aegis" ]; then rm -f "/etc/runlevels/default/aegis" > /dev/null 2>&1; fi
	elif [ -f /etc/init.d/aegis ]; then
		/etc/init.d/aegis  uninstall
		for ((i=2;i<=5;i++)); do
			if [ -d "/etc/rc${i}.d/" ]; then rm -f "/etc/rc${i}.d/S80aegis"; elif [ -d "/etc/rc.d/rc${i}.d" ]; then rm -f "/etc/rc.d/rc${i}.d/S80aegis"; fi
		done
	fi
	printf "%-40s %40s\n" "Uninstall aegis Service" "[ OK ]"
}
uninstall_aegis_quartz() {
	echo ""
	echo "Uninstall aegis And quartz ..."
	stop_aegis_quartz
	uninstall_aegis_service
	if [ -d /usr/local/aegis ]; then
		rm -rf /usr/local/aegis/aegis_client > /dev/null 2>&1
		rm -rf /usr/local/aegis/aegis_update > /dev/null 2>&1
		rm -rf /usr/local/aegis/alihids > /dev/null 2>&1
	fi
	if [ -d /usr/local/aegis ]; then
		rm -rf /usr/local/aegis/aegis_quartz > /dev/null 2>&1
	fi
	rm -rf /usr/local/aegis > /dev/null 2>&1
	rm -rf /usr/local/aegis* > /dev/null 2>&1
	rm -rf /usr/sbin/aliyun-service > /dev/null 2>&1
	rm -rf /etc/systemd/system/aliyun.service > /dev/null 2>&1
	rm -rf /lib/systemd/system/aliyun.service > /dev/null 2>&1
	rm -rf /etc/init.d/agentwatch > /dev/null 2>&1
	rm -rf /usr/sbin/aliyun-service.backup > /dev/null 2>&1
	rm -rf /usr/sbin/aliyun_installer > /dev/null 2>&1
	rm -rf /usr/local/share/aliyun-assist > /dev/null 2>&1
	umount /usr/local/aegis/aegis_debug > /dev/null 2>&1
	printf "%-40s %40s\n" "Uninstall aegis And quartz" "[ OK ]"
}
welcome_marks() {
	cat > /etc/motd << EOF

-------------------------------------------------------------------------
-	                  ! Welcome Back 	                	-
-------------------------------------------------------------------------
-------------------------------------------------------------------------
EOF
}
##################### Clean Up Aliyun End #####################

# Only Set ssh Login By RSA Key
if [ "$ONLY_SSH_KEY_AUTH" = "ssh-key" ]; then
	set_rsa_authentication
	exit 0
fi
# Set Time Zone
timedatectl set-local-rtc 1
timedatectl set-timezone Asia/Shanghai
enable_ssh
# Aliyun Clean Up
if [ "$ALIYUN_HOST" = "YES" ]; then
	replace_yum_source
	uninstall_aegis_quartz
	firewall_default
	welcome_marks
fi
#disable_selinux
install_base_packages

# Create User and RSA Key
if [ "$ADD_USER_AND_KEY" = "YES" ]; then create_user_and_rsakey_file; fi

# Set ssh Login By RSA Key
#set_rsa_authentication

echo ""
echo "################### SETUP DONE! ###################"
if [ "$ADD_USER_AND_KEY" = "YES" ]; then
	echo "----------------------------------------------------"
	echo -e "Remember This User: ${yellow}${NEW_USER}${plain}, And The Password"
	echo -e "${red}BACKUP${plain} Keys Files: \"${yellow}${CUR_DIR}/${RSA_KEY_NAME}${plain}\""
	echo "----------------------------------------------------"
fi
echo -e "############ Must be ${red}reboot${plain} the SYSTEM. ############"
echo ""
exit 0
###########################################################



