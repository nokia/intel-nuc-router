#!/bin/bash

# Enable/disable debugging
#set -x

# Name of the traffic control command.
TC_CMD=/sbin/tc
TC="sudo $TC_CMD"
if [ ! -x $TC_CMD ]
then
	yum -y install iproute
fi

# The network interfaces we're planning on limiting bandwidth.
if [ -f .nic.internal ] && [ -f .nic.external ]
then
	# Need to perform shaping in both directions
	#  Shaping rules have to be applied on two interfaces

	UP_IF=`cat .nic.external`
	# Specify the external subnet to be rate-limited/throttled
	UP_IP=`ip addr show $UP_IF | grep inet | grep -v inet6 | awk '{print $2}'`
        echo "Using external interface: $UP_IF with address $UP_IP"

	DL_IF=`cat .nic.internal`
	# Specify the internal subnet to be rate-limited/throttled
        DL_IP=`ip addr show $DL_IF | grep inet | grep -v inet6 | awk '{print $2}'`
	echo "Using internal interface: $DL_IF with address $DL_IP"
else
	echo "Error: unable to identify active interfaces"
	echo "Specify external interface in file: .nic.external"
	echo "Specify internal interface in file: .nic.internal"
fi
echo ""

start() {

#  tc uses the following units when passed as a parameter.

echo "Traffic shaping bandwidth can be specified as:"
echo "  kbps: Kilobytes per second"
echo "  mbps: Megabytes per second"
echo "  kbit: Kilobits per second"
echo "  mbit: Megabits per second"
echo "  bps: Bytes per second"
echo ""

echo -n "Specify upload bandwidth: "; read UP_BW
echo -n "Specify download bandwidth: "; read DL_BW
echo ""

#       Amounts of data can be specified in:
#       kb or k: Kilobytes
#       kbit: Kilobits
#  To get the byte figure from bits, divide the number by 8 bit

# We'll use Hierarchical Token Bucket (HTB) to shape bandwidth.
# For detailed configuration options, please consult Linux man
# page.

    $TC qdisc add dev $UP_IF root handle 1: htb default 30
    $TC class add dev $UP_IF parent 1: classid 1:1 htb rate $UP_BW
    $TC class add dev $UP_IF parent 1: classid 1:2 htb rate $UP_BW

    $TC qdisc add dev $DL_IF root handle 1: htb default 30
    $TC class add dev $DL_IF parent 1: classid 1:1 htb rate $DL_BW
    $TC class add dev $DL_IF parent 1: classid 1:2 htb rate $DL_BW

    # Filter options for limiting the intended interface.

    $TC filter add dev $UP_IF protocol ip parent 1:0 prio 1 u32 match ip src $UP_IP flowid 1:1
    $TC filter add dev $UP_IF protocol ip parent 1:0 prio 1 u32 match ip dst $DL_IP flowid 1:2
    $TC filter add dev $DL_IF protocol ip parent 1:0 prio 1 u32 match ip src $UP_IP flowid 1:1
    $TC filter add dev $DL_IF protocol ip parent 1:0 prio 1 u32 match ip dst $DL_IP flowid 1:2

# For each interface...
#
#  The first line creates the root qdisc, and the next two lines
#  create two child qdisc that are to be used to shape download
#  and upload bandwidth.
#
#  The 4th and 5th line creates the filter to match the interface.
#  The 'dst' IP address is used to limit download speed, and the
#  'src' IP address is used to limit upload speed.
}

stop() {

# Stop the bandwidth shaping.
if ($TC qdisc del dev $UP_IF root >/dev/null 2>&1) && ($TC qdisc del dev $DL_IF root >/dev/null 2>&1)
then
	return
else
	echo "ERROR"
	echo "Shaping is not currently configured"; exit 1
fi	
}

restart() {

# Self-explanatory.
    stop
    sleep 1
    start
}

show() {

# Display status of traffic control status.
    echo "Bandwidth shaping rules for external interface: $UP_IF"
    $TC -s qdisc ls dev $UP_IF
    echo ""
    echo "Bandwidth shaping rules for external interface: $DL_IF"
    $TC -s qdisc ls dev $DL_IF
}

case "$1" in

  start)

    start
    echo "Traffic shaping rules configured"
    ;;

  stop)

    echo -n "Stopping bandwidth shaping: "
    stop
    echo "done"
    ;;

  restart)

    echo -n "Restarting bandwidth shaping: "
    restart
    echo "done"
    ;;

  show)

    show
    echo ""
    ;;

  *)

    pwd=$(pwd)
    echo "Usage: bandwidth-shaping.sh {start|stop|restart|show}"
    ;;

esac

exit 0
