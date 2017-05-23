#!/bin/bash

# set -x

source definitions

if [ -d centos7-nginx ]
then
	NGINX_IP=`docker inspect --format '{{ .NetworkSettings.IPAddress }}' centos7-nginx`
fi

if [ -d centos7-nginx-rtmp ]
then
	NGINX_RTMP_IP=`docker inspect --format '{{ .NetworkSettings.IPAddress }}' centos7-nginx-rtmp`
fi

if [ ! -f .nic.internal ] || [ ! -f .nic.external ]
then
echo "ERROR: Unable to automatically identify active network interfaces"
echo " This script must be run after the router build script"
echo " Also, it can only be run from the router build script directory"
exit 1
fi

disable() {
# Disables firewalld
#  This function is "hidden" from the command-line help
systemctl mask firewalld > /dev/null 2>&1
sudo systemctl disable firewalld > /dev/null 2>&1
sudo systemctl stop firewalld > /dev/null 2>&1
}

filterAccess() {
echo "Restricting SSH/HTTP/HTTPS access to RFC1918 addresses"
# Allow already established connections through
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
# Allow access only from RFC1918 addresses
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 22 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 22 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 22 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 80 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 80 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 80 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 443 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 443 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 443 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 1935 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 1935 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 1935 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 3129 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 3129 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 3129 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 10.0.0.0/8 --dport 8080 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 172.16.0.0/12 --dport 8080 -j ACCEPT
sudo iptables -A INPUT -m state --state NEW -m tcp -p tcp -s 192.168.0.0/16 --dport 8080 -j ACCEPT
# Block everything else
#sudo iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited
#sudo iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited
iptables -N LOGGING
iptables -A INPUT -j LOGGING
iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
iptables -A LOGGING -j DROP
}

buildAkamai() {
echo "Attempt to add Akamai rule to NGINX configuration?"
read -n 1 -p "Enter [y/n]: " RESPONSE
case $RESPONSE in
y|Y  ) echo ""; :;;
n|N  ) echo ""; buildRedirection;;
* ) echo ""; echo "ERROR: Invalid selection, aborting operation!"; exit 1;;
esac

echo "Sample Akamai domain name: $AKAMAI_PREFIX"
echo "Domain must include protocol prefix (e.g. http://) but no path suffix"
echo -n "Enter Akamai domain to cache: "; read AKAMAI_PREFIX

# Add corresponding entries to NGINX configuration file
echo '    location ~* ^\/.*\.mpd$ {' >> $NGINX_REDIR_CONF
echo "    proxy_pass $AKAMAI_PREFIX;" >> $NGINX_REDIR_CONF
echo '    add_header X-Proxy-Cache $upstream_cache_status; }' >> $NGINX_REDIR_CONF
echo "" >> $NGINX_REDIR_CONF
echo "    location ~* ^\/.*\.(m4s|mp4|m4v)$ {" >> $NGINX_REDIR_CONF
echo "    proxy_cache my_cache;" >> $NGINX_REDIR_CONF
echo "    proxy_ignore_headers Cache-Control Expires Set-Cookie;" >> $NGINX_REDIR_CONF
echo "    proxy_cache_valid any 120m;" >> $NGINX_REDIR_CONF
echo '    add_header X-Proxy-Cache $upstream_cache_status;' >> $NGINX_REDIR_CONF
echo "    proxy_pass $AKAMAI_PREFIX;" >> $NGINX_REDIR_CONF
echo '    proxy_cache_key $request_uri;' >> $NGINX_REDIR_CONF
echo "    proxy_cache_lock on; }" >> $NGINX_REDIR_CONF
echo "" >> $NGINX_REDIR_CONF

echo "Added NGINX configuration for Akamai distribution"
echo "Attempting to resolve the Akamai domain to the source/origin servers"
echo "Note: These IP addresses will need to be manually entered below"
echo "This is because IPTABLES cannot perform interception based on domains/names"

AKAMAI_DOMAIN=`echo $AKAMAI_PREFIX | sed "s#http://##g" | sed "s#https://##g"`
host $AKAMAI_DOMAIN
}

validateAddress()
{
# Function to validate string is IP address
#  returns true if supplied with IPv4 address

# Credit:
#  http://www.linuxjournal.com/content/validating-ip-address-bash-script

local  ip=$1
local  stat=1

if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
OIFS=$IFS
IFS='.'
ip=($ip)
IFS=$OIFS
[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
stat=$?
fi
return $stat
}

save() {

# First ensure we are blocking access to local services
filterAccess

# Save IPTABLES state and copy NGINX redirect configuration into place
if (sudo iptables-save > /etc/sysconfig/iptables 2>&1)
then
	echo "IPTABLES rules saved successfully for reboot persistence"; exit 0
else
	echo "ERROR: IPTABLES rules could not be saved"; exit 1
fi
}

flush() {
echo "WARNING:  Flushing all existing IPTABLES rules"
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X
sudo iptables -t raw -F
sudo iptables -t raw -X
}

list() {
# Displays the full IPTABLES configuration
echo "Listing all IPTABLES rules"
sudo iptables -t nat -L -n -v
}
view() {
list
}

detect() {
# Interface selection
INSIDE_NIC=`cat .nic.internal`
if [ ! -d /sys/class/net/$INSIDE_NIC ]
then
echo "Adapter NOT found: /sys/class/net/$INSIDE_NIC"
echo "Correct device/path and run setup again"; exit 1
else
INSIDE_ADDR=`ip addr show dev $INSIDE_NIC | grep "inet " | grep $INSIDE_NIC | awk '{print $2}' | awk -F'/' '{print $1}'`
INSIDE_SUBNET=`ip route | grep $INSIDE_NIC | grep -v default | awk '{print $1}'`
echo "Internal network: $INSIDE_NIC $INSIDE_ADDR $INSIDE_SUBNET"
fi

OUTSIDE_NIC=`cat .nic.external`
if [ ! -d /sys/class/net/$OUTSIDE_NIC ]
then
echo "Adapter NOT found: /sys/class/net/$OUTSIDE_NIC"
echo "Correct device/path and run setup again"; exit 1
else
OUTSIDE_ADDR=`ip addr show dev $OUTSIDE_NIC | grep "inet " | grep $OUTSIDE_NIC | awk '{print $2}'| awk -F'/' '{print $1}'`
OUTSIDE_SUBNET=`ip route | grep $OUTSIDE_NIC | grep -v default | grep -v via | awk '{print $1}'`
echo "External network: $OUTSIDE_NIC $OUTSIDE_ADDR $OUTSIDE_SUBNET"
fi

if [ -z $INSIDE_ADDR ] || [ -z $OUTSIDE_ADDR ] || [ -z $INSIDE_SUBNET ] || [ -z $OUTSIDE_SUBNET ]
then
	echo "Unable to enumerate IP addresses: a network adapter may be down"
	echo "Check cabling and if necessary connect to a switch/hub"
	exit 1
fi
}

masquerade() {
echo "Enabling IP NAT masquerading"
detect
#flush
# Create/build IPTABLES rules
if (sudo iptables -t nat -L -n -v | grep MASQUERADE | grep $OUTSIDE_NIC > /dev/null 2>&1)
then
echo "Existing masquerading rule may already be in place"
echo "Not adding potential duplicates!"; exit 0
else
echo "Enabling IP masquerading on outside interface"
#sudo iptables -t nat -A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $OUTSIDE_NIC -s $PREFIX.0/24 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_IP -d $NGINX_IP --dport 3129 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_IP -d $NGINX_IP --dport 8081 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_RTMP_IP -d $NGINX_RTMP_IP --dport 8082 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_RTMP_IP -d $NGINX_RTMP_IP --dport 1935 -j MASQUERADE
sudo iptables -t mangle -A PREROUTING -p tcp --dport $REDIR_PORT -j DROP
#sudo iptables -t nat -N DOCKER
#sudo iptables -t nat -A DOCKER -j RETURN -i docker0
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 3129 -j DNAT --to-destination $NGINX_IP:3129
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 80 -j DNAT --to-destination $NGINX_IP:8081
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 8082 -j DNAT --to-destination $NGINX_RTMP_IP:8082
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 1935 -j DNAT --to-destination $NGINX_RTMP_IP:1935
#sudo iptables -t nat -A OUTPUT -j DOCKER ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL
#sudo iptables -t nat -A PREROUTING -j DOCKER -m addrtype --dst-type LOCAL
fi
save
}

promptToAddAgain() {
echo "Attempt to add another rule to IPTABLES?"
read -n 1 -p "Enter [y/n]: " RESPONSE
case $RESPONSE in
y|Y  ) echo ""; buildRedirection;;
n|N  ) echo ""; :;;
* ) echo ""; echo "ERROR: Invalid selection, aborting operation!"; exit 1;;
esac
}

buildRedirection() {
echo "Enter source/origin IP address to be intercepted and redirected"
echo -n "IP address: "; read REDIR_ADDRESS
if (validateAddress $REDIR_ADDRESS)
then
echo "Creating IPTABLES rule for $REDIR_ADDRESS"
if (sudo iptables -t nat -A PREROUTING -p tcp -s $INSIDE_SUBNET -d $REDIR_ADDRESS --dport 80 -j REDIRECT --to-port $REDIR_PORT)
then
echo "Created IPTABLES rule successfully"

# Add corresponding entries to NGINX configuration file
echo '    location ~* ^\/.*\.mpd$ {' >> $NGINX_REDIR_CONF
echo "    proxy_pass http://$REDIR_ADDRESS;" >> $NGINX_REDIR_CONF
echo '    add_header X-Proxy-Cache $upstream_cache_status; }' >> $NGINX_REDIR_CONF
echo "" >> $NGINX_REDIR_CONF
echo "    location ~* ^\/.*\.(m4s|mp4|m4v)$ {" >> $NGINX_REDIR_CONF
echo "    proxy_cache my_cache;" >> $NGINX_REDIR_CONF
echo "    proxy_ignore_headers Cache-Control Expires Set-Cookie;" >> $NGINX_REDIR_CONF
echo "    proxy_cache_valid any 120m;" >> $NGINX_REDIR_CONF
echo '    add_header X-Proxy-Cache $upstream_cache_status;' >> $NGINX_REDIR_CONF
echo "    proxy_pass http://$REDIR_ADDRESS;" >> $NGINX_REDIR_CONF
echo '    proxy_cache_key $request_uri;' >> $NGINX_REDIR_CONF
echo "    proxy_cache_lock on; }" >> $NGINX_REDIR_CONF
echo "" >> $NGINX_REDIR_CONF

else
echo "Error creating IPTABLES rule"
fi
promptToAddAgain
else
echo "ERROR: String supplied was not valid IPv4 address"
promptToAddAgain
fi
}

intercept() {
# Create/build IPTABLES rules
echo "Building IPTABLES rules for TCP/80 -> local TCP/$REDIR_PORT traffic redirection"
detect
# Flushing existing IPTABLES ruleset
flush
sudo iptables -t nat -A PREROUTING -s 127.0.0.1 -p tcp --dport 80 -j ACCEPT
sudo iptables -t nat -A PREROUTING -s $INSIDE_ADDR -p tcp --dport 80 -j ACCEPT
sudo iptables -t nat -A PREROUTING -s $OUTSIDE_SUBNET -p tcp --dport 80 -j ACCEPT

# Build headers of nginx configuration file
cat > $NGINX_REDIR_CONF <<'EOF'
# NOTE: redirecting traffic not located at the origin servers below
#  will result in the NGINX server returning 404 errors to clients!
# It is CRITICAL that traffic interception rules only redirect appropriate traffic

proxy_cache_path /home/nginx levels=1:2 keys_zone=my_cache:10m max_size=10g inactive=120m;

server {

    #listen *:3129;
    listen [::]:3129 ipv6only=off;

EOF

# Offer to add Akamai specific NGINX configuration
buildAkamai

# Redirection can take place for multiple IP addresses, therefore the section
#  below can be called mutiple times in a loop until all the required addresses have been added
buildRedirection

# Add the final closing rules to IPTABLES
#  typically these are to avoid redirecting traffic in a loop
echo "Adding closing rules/statements"
#sudo iptables -t nat -A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $OUTSIDE_NIC -s $INSIDE_SUBNET -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_IP -d $NGINX_IP --dport 3129 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_IP -d $NGINX_IP --dport 8081 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_RTMP_IP -d $NGINX_RTMP_IP --dport 8082 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -p tcp -s $NGINX_RTMP_IP -d $NGINX_RTMP_IP --dport 1935 -j MASQUERADE

sudo iptables -t mangle -A PREROUTING -p tcp --dport $REDIR_PORT -j DROP
#sudo iptables -t nat -N DOCKER
#sudo iptables -t nat -A DOCKER -j RETURN -i docker0 
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 3129 -j DNAT --to-destination $NGINX_IP:3129
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 80 -j DNAT --to-destination $NGINX_IP:8081
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 8082 -j DNAT --to-destination $NGINX_RTMP_IP:8082
#sudo iptables -t nat -A DOCKER -p tcp ! -i docker0 --dport 1935 -j DNAT --to-destination $NGINX_RTMP_IP:1935
#sudo iptables -t nat -A OUTPUT -j DOCKER ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL
#sudo iptables -t nat -A PREROUTING -j DOCKER -m addrtype --dst-type LOCAL

# Add closing parenthesis to NGINX cache configuration
echo "}" >> $NGINX_REDIR_CONF

echo "Note: rules for traffic interception are of the form:"
echo "	sudo iptables -t nat -A PREROUTING -p tcp -s $PREFIX.0/24 -d SUBNET/24 --dport 80 -j REDIRECT --to-port 3129"

if (systemctl | grep docker-nginx > /dev/null 2>&1)
then
    # If NGINX is running under docker
    echo "Attempting to identify docker container"
    CONTAINER_ID=`docker ps | grep $NGINX_CONTAINER$ | awk '{print $1}'`
    echo "Copying updated NGINX redirect/intercept configuration to server"
    docker cp $NGINX_REDIR_CONF $CONTAINER_ID:/etc/nginx/conf.d/
    echo "Reloading NGINX configuration in docker container"
    docker exec $CONTAINER_ID nginx -s reload
elif [ -f /etc/nginx/nginx.conf ]
then
    echo "Copying configuration to local/native NGINX"
    cp $NGINX_REDIR_CONF /etc/nginx/conf.d/
    echo "Reloading local/native NGINX"
    nginx -s reload
fi

# Save IPTABLES rules to make the persistent across reboots
save
}

menu() {
echo "Configuring IPTABLES ruleset"
read -n 1 -p "Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: " RESPONSE
case $RESPONSE in
f|F  ) echo ""; flush;;
l|L  ) echo ""; list;;
v|V  ) echo ""; view;;
m|M  ) echo ""; masquerade;;
i|I  ) echo ""; intercept;;
s|S  ) echo ""; save;;
d|D  ) echo ""; disable;;
* ) echo ""; echo "Aborting operation!"; exit 1;;
esac
}

if [ $# -eq 0 ]
then
disable
menu
elif [ $# -eq 1 ]
then
$1
else
echo "Usage:    $0 [optional method call]"; exit 1
fi
