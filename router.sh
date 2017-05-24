#!/bin/bash

# Optional debugging flags
#set -x

set +m # disable job control in order to allow lastpipe
shopt -s lastpipe

source definitions

########## Due dilligence

CURRENT_USER=`whoami`
if [ ! $CURRENT_USER == root ]
then
        echo "This script needs sudo access to run priviledged commands"
	echo "Depending on your permissions, you may want to run it as root"
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 1>&2
   exit 1
fi

# The script take zero or one arguments
#  Specify "interactive" to have the script prompt for NICs

if [ $# -ne 0 ] && [ $# -ne 1 ]
then
	echo "Usage:	$0 [interactive]"; exit 1

elif [ $# -eq 1 ] && [ $1 = interactive ]
then
	INTERACTIVE=true
fi

##### Freshen system
freshenSystem() {
yum -y update
yum -y install epel-release
yum -y install git lshw yum-cron which less policycoreutils-python yum-utils wget curl bind-utils net-tools telnet nmap-ncat httpd-tools nmap dhcp ntp iptables-services zip unzip nload iftop

# Reboot system if running the script for the first time
if [ ! -f .nic.internal ]
then
	touch .nic.internal
	echo "Restarting system after initial OS updates, press ctrl-c to abort"
	echo "Run the script a second time when the system comes back up!"
	sleep 15
	sudo shutdown -r now
fi
}

##### DetectUSBNIC

detectUSBNIC() {
	LSHW=`which lshw`
	if [ ! -x $LSHW ]
	then
		echo "LSHW binary not found in path"; exit 1
	else
		$LSHW -C network | grep -A 6 $USB_NIC_CHIPSET | grep "logical name" | awk '{print $3}'
	fi
}

##### Install external LTS-KERNEL
installKernel() {
# Code below is unsafe on latest Intel NUC hardware
#  We will no longer update the kernel and will rely on CentOS defaults going forward

echo "Installing Mainline Linux kernel"
sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
sudo yum -y install http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
sudo yum -y --enablerepo=elrepo-kernel install kernel-lt

# The grub setup might change over time, hopefully not often
if [ -f /etc/grub2-efi.cfg ]
then
        GRUB_FILE="/etc/grub2-efi.cfg"
elif [ -f /etc/grub2.cfg ]
then
        GRUB_FILE="/etc/grub2.cfg"
fi
echo "GRUB configuration file is: $GRUB_FILE"

echo "Cleaning up older kernel packages"
sudo package-cleanup --oldkernels --count=3
NUM_KERNELS=`awk -F\' '/menuentry / {print $2}' $GRUB_FILE | wc -l`
echo "Number of kernel boot entries: $NUM_KERNELS"
KERN_STRING=`awk -F\' '/menuentry / {print $2}' $GRUB_FILE | grep elrepo | sort -r | uniq | head -1`
echo "Kernel to boot: $KERN_STRING"
echo "Setting new kernel to boot by default"
sudo grub2-set-default "$KERN_STRING"
}

########## Main script entry point

echo "The system will automatically reboot once the script completes"
freshenSystem
echo "Enabling automatic system software updates"
systemctl enable yum-cron
systemctl start yum-cron

# External NIC detection
echo "We will attempt to auto-detect network interfaces to configure the router"
echo "The interface hosting the current default route will be designated external"
echo "The NUC should have its embedded NIC connected to an Internet connection"; sleep 5
NICDETECT1=`ip route | grep default | grep "metric 100" | awk '{print $5}'`
NICDETECT2=`ls /sys/class/net | grep -v lo | grep $NICDETECT1`
EXTNIC="$NICDETECT1"

if (ls /sys/class/net | grep $EXTNIC > /dev/null 2>&1)
then
        echo "Detected network device with default route: $EXTNIC"
	sudo echo $EXTNIC > .nic.external
else
        INTERACTIVE="true"
fi

# Internal NIC detection
echo "A USB/Gigabit Ethernet adapter MUST BE CONNECTED BEFORE PROCEEDING"
echo "If not connected, insert adapter into USB port NOW!!!"; sleep 15
USBNIC=`detectUSBNIC`
if (ls /sys/class/net | grep $USBNIC > /dev/null 2>&1)
then
	echo "Detected network device with $USB_NIC_CHIPSET chipset: $USBNIC"
	echo "Proceeding to configure device as internal network with DHCP"
	sudo echo $USBNIC > .nic.internal
else
	INTERACTIVE="true"
fi

# Interactive NIC specification
if [ $INTERACTIVE == true ]
then
	echo "This system has the following network interfaces: "
	ls /sys/class/net | grep -v lo | grep -v docker0
	echo -n "Designate the external/internet interface/device: "
	read EXTNIC
	echo "The internal/private network should be hosted on a USB3 adapter"
	echo -n "Designate the internal interface/device: "
	read USBNIC
fi

if (ls /sys/class/net | grep $EXTNIC > /dev/null 2>&1) && (ls /sys/class/net | grep $USBNIC > /dev/null 2>&1)
then
	echo "Two working adapters confirmed, continuing..."; sleep 2
else
	echo "The presence of one or more adapters could not be verified"
	echo "Check your system's network setup and try again"; exit 1
fi

# Storing NIC configuration in persistent files
sudo echo $EXTNIC > .nic.external
sudo echo $USBNIC > .nic.internal

# Configure inside interface with static addressing
INT_CFG_FILE=/etc/sysconfig/network-scripts/ifcfg-$USBNIC
sudo echo "TYPE=Ethernet" > $INT_CFG_FILE
sudo echo "BOOTPROTO=static" >> $INT_CFG_FILE
sudo echo "DEFROUTE=no" >> $INT_CFG_FILE
sudo echo "IPV4_FAILURE_FATAL=no" >> $INT_CFG_FILE
sudo echo "IPV6INIT=no" >> $INT_CFG_FILE
sudo echo "IPV4_FAILURE_FATAL=no" >> $INT_CFG_FILE
sudo echo "NAME=$USBNIC" >> $INT_CFG_FILE
sudo echo "DEVICE=$USBNIC" >> $INT_CFG_FILE
sudo echo "ONBOOT=yes" >> $INT_CFG_FILE
sudo echo "IPADDR=$ROUTER" >> $INT_CFG_FILE
sudo echo "NETMASK=$NETMASK" >> $INT_CFG_FILE

echo -n "Enabling packet forwarding between interfaces: "
sudo sysctl -w net.ipv4.ip_forward=1
if [ -f /etc/sysctl.d/ip_forward.conf ]
then
	sudo rm /etc/sysctl.d/ip_forward.conf
fi
sudo echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/ip_forward.conf

echo "Enabling TCP/IP stack optimisations"
sudo sysctl -w net.ipv4.tcp_low_latency=1
sudo sysctl -w net.core.netdev_max_backlog=4000
sudo sysctl -w net.ipv4.ip_local_port_range="10000 65535"
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=16384
sudo echo "net.ipv4.tcp_low_latency = 1"  > /etc/sysctl.d/ip_stack_tweaks.conf
sudo echo "net.core.netdev_max_backlog = 4000" >> /etc/sysctl.d/ip_stack_tweaks.conf
sudo echo "net.ipv4.ip_local_port_range = 10000 65535" >> /etc/sysctl.d/ip_stack_tweaks.conf
sudo echo "net.ipv4.tcp_max_syn_backlog = 16384" >> /etc/sysctl.d/ip_stack_tweaks.conf

# Enable DHCP server on inside interface
sudo cat <<EOF > /etc/dhcp/dhcpd.conf
log-facility local0;
option domain-name "internal.net";
option domain-name-servers 8.8.8.8, 8.8.4.4;
default-lease-time 3600;
max-lease-time 7200;
authoritative;
subnet $SUBNET netmask $NETMASK {
    range dynamic-bootp $PREFIX.100 $PREFIX.200;
    option broadcast-address $BROADCAST;
    option routers $ROUTER; }

# Wireless access point static IP reservations
host xirrus-ap1 {
	hardware ethernet 48:c0:93:0f:46:f2;
       	fixed-address 192.168.96.11;
}
host xirrus-ap2 {
	hardware ethernet 48:c0:93:0f:48:76;
	fixed-address 192.168.96.12;
}
host xirrus-ap3 {
        hardware ethernet 48:c0:93:0f:47:da;
        fixed-address 192.168.96.13;
}
host xirrus-ap4 {
        hardware ethernet 48:c0:93:0f:47:28;
        fixed-address 192.168.96.14;
}
host xirrus-ap5 {
        hardware ethernet 48:c0:93:0f:47:10;
        fixed-address 192.168.96.15;
}
host xirrus-ap6 {
        hardware ethernet 48:c0:93:0f:29:d6;
        fixed-address 192.168.96.16;
}
EOF

if [ ! -h /etc/systemd/system/multi-user.target.wants/dhcpd.service ]
then
	sudo ln -s '/usr/lib/systemd/system/dhcpd.service' '/etc/systemd/system/multi-user.target.wants/dhcpd.service'
fi

if !(grep /var/log/dhcpd.log /etc/rsyslog.conf >/dev/null)
then
	echo "Adding local0.debug entry to /etc/rsyslog.conf"
	sudo echo "local0.debug						/var/log/dhcpd.log" >> /etc/rsyslog.conf
fi

# Try to avoid listening on anything but the internal/private network interface
# sudo echo "DHCPDARGS=\"$USBNIC\"" > /etc/sysconfig/dhcpd
# Restore classic DHCPD behaviour to CentOS 7
sudo cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/
# sudo sed -i 's:dhcpd --no-pid:dhcpd --no-pid $DHCPDARGS:' /etc/systemd/system/dhcpd.service

echo "Restarting networking"
sudo systemctl restart network

sudo systemctl enable dhcpd > /dev/null 2>&1
sudo systemctl daemon-reload
sudo systemctl restart dhcpd.service > /dev/null 2>&1

# Enable IPTABLES service
echo "Enabling IPTABLES service"
sudo systemctl enable iptables.service

if [ ! -f .set-hostname ]
then
	hostnamectl set-hostname nuc-router
fi

# Enable IP masquerading in IPTABLES
#  This needs to be done after Docker is installed
systemctl enable iptables > /dev/null 2>&1
sudo ./iptables.sh disable
sudo ./iptables.sh masquerade

echo "Script completed successfully"; exit 0
