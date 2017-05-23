#!/bin/bash

#set -x

NLOAD=`which nload > /dev/null 2>&1`
IFTOP=`which iftop > /dev/null 2>&1`

if !(which nload > /dev/null 2>&1)
then
	echo "Missing nload binary"
	sudo yum -y install epel-release
	sudo yum -y install nload
fi
if !(which iftop > /dev/null 2>&1)
then
	echo "Missing iftop binary"
        sudo yum -y install epel-release
	sudo yum -y install iftop
fi

#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root!" 1>&2
#   exit 1
#fi

useNload() {
	nload -i 4000 devices -t 2000 $NIC
}
useIftop() {
	echo "Note: The IFTOP utility requires root permissions"; sleep 1
	sudo iftop -n -i $NIC
}

echo "Monitor interface traffic throughput"

chooseNIC() {
	echo "Available network interfaces:"
	echo -n "       "; ls /sys/class/net/
	echo "Specify network device to use: "
	read NIC
	if [ ! -h /sys/class/net/$NIC ]
	then
		echo "The specified network interface was NOT FOUND"; exit 1
	fi
}

if [ -f .nic.internal ] && [ -f .nic.external ]
then
	echo "Detected network interfaces:"
	echo -n "Internal: "; cat .nic.internal
	NIC_INT=`cat .nic.internal`
	echo -n "External: "; cat .nic.external
	NIC_EXT=`cat .nic.external`

	# ---------- DEBUGGING SECTION BELOW
	#echo "Other devices: "
	#ls /sys/class/net/ | grep -v $NIC_INT | grep -v $NIC_EXT

	read -n 1 -p "Choose [i]nternal, [e]xternal, or [o]ther interface: " RESPONSE
	case $RESPONSE in
	 i|I  ) echo ""; NIC=$NIC_INT
	;;
	 e|E  ) echo ""; NIC=$NIC_EXT
	;;
	 o|O  )	echo ""; chooseNIC
	;;
	 * ) echo ""; echo "Aborting operation!"; exit 1;;
	esac
else
	chooseNIC
fi

read -n 1 -p "Choose [n]load or [i]ftop: " RESPONSE
case $RESPONSE in
 n|N  ) echo ""; useNload;;
 i|I  ) echo ""; useIftop;;
 * ) echo ""; echo "Aborting operation!"; exit 1;;
esac
