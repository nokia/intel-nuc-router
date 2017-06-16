# Intel NUC Router

This source code repository contains the shell scripts necessary to configure and manage an Intel NUC consumption box router. It is marked public, which means it is possible to anonymously browse the code and clone the repository.

The consumption box performs a number of different tasks:

* Acts as a router and Internet gateway device
* Can bandwidth throttle traffic traversing interfaces
* Can optionally be configured with an NGINX server to host MPEG-DASH streams
* Can use IPTABLES to redirect traffic to an NGINX proxy/cache
* Can potentially be used for transcoding video streams (work not completed yet)

## Router Capabilities

The router performs NAT between an internal (private) network and an external (Internet) connection. To do this, a USB3/Gigabit Ethernet adapter is required in addition to the basic Intel NUC hardware. We've successfully used adapters based on the ASIX AX88179 chipset (no others have been tested at this time). The router also runs a DHCP server, so that clients can be configured to automatically obtain their network configuration. It is possible to add static DHCP reservations so that servers and wireless access points receive consistent IP addressing (which is particularly important at certain events, such as when live streaming is being demonstrated). While acting as a router, it is possible to throttle network traffic between the internal and external network interfaces. This is useful for simulating environments and network conditions, such as home broadband connections. Tools have also been packaged with the router to allow traffic on the interfaces to be monitored.

## Hardware Specification

To build a consumption box router, you will need:

* An Intel NUC micro server
* Memory and SSD storage modules for the NUC (need to be purchased separately from NUC)
* A USB3/Gigabit Ethernet adapter (ASIX AX88179 chipset recommended)

Intel's product pages for the NUC can be found here:

http://www.intel.com/content/www/us/en/nuc/overview.html

We have purchased the following items in the past:

https://www.bhphotovideo.com/bnh/controller/home?O=email&A=details&Q=&sku=1316110&is=REG<br>
https://www.bhphotovideo.com/bnh/controller/home?O=email&A=details&Q=&sku=1193709&is=REG<br>
https://www.bhphotovideo.com/bnh/controller/home?O=email&A=details&Q=&sku=1083306&is=REG<br>
https://www.amazon.com/Plugable-Gigabit-Ethernet-Network-Adapter/dp/B00AQM8586/

However, I'd recommend going with the Core i5 processor models, if possible:

http://www.intel.com/content/www/us/en/nuc/nuc-kit-nuc7i5bnk.html

## Building a NUC as a Consumption Box/Router

Install a minimal installation of CentOS 7 on the NUC hardware and connect the onboard Ethernet interface to a network with Internet access. Ensure that the adapter is up and that network access is available between reboots. At this time, it is not recommended to build the NUC from a wifi network, as the scripts may not work correctly.

The router build process only involves a handful of steps:

* Perform a minimal install of CentOS 7 Linux on the NUC
* Connect the NUC embedded Ethernet adapter to a wired network with Internet access
* Clone the GIT repository hosting the router build code (or alternatively, uncompress a software archive containing the build scripts)
* Run the router.sh UNIX shell script to configure the system

When connected to Nokia internal networks, the build process is as follows (from the console):

    $ sudo -i
    # yum -y install git
    # git clone https://github.com/nokia/intel-nuc-router.git
    # cd intel-nuc-router
    # ./router.sh

The build script will perform a partial system configuration and will reboot half way through. This is necessary for the external USB3/Gigabit Ethernet adapter to be reliably detected. Log back in, sudo to root, and invoke the router.sh script a second time:

    $ sudo -i
    # ./router.sh

This time the script will attempt to detect and configure the network interfaces and enable DHCP on the inside NIC.

Some common problems you may encounter with the build process are:

* Broken Internet access (or non functioning DNS) will prevent the installation from proceeding
* Network interfaces need to be enabled or they may not be detected correctly

It should be possible to test that the NUC is functioning as a router by connecting a computer to the USB3/Gigabit Ethernet adapter. The computer should have working network access through the NUC, but using private addressing from the pool 192.168.96.0/24. This addressing will be different from the network that the NUC is using to get Internet access (through the embedded NIC).

At this point, only basic router functionality will be working. You now need to install NGINX using the code and instructions here:

https://github.com/mwatkins-nt/nginx-config

## Router Management and Monitoring

Alongside the router build script, you will find several other shell scripts to manage the system:

    bwshaping.sh
    iptables.sh
    monitoring.sh

We will take a detailed look at each of these scripts in turn.

### Bandwidth Shaping

The bandwidth shaping script can simulate slower network speeds by using a feature of the Linux kernel to modify the interface queuing parameters. A detailed description of how this works is beyond the scope of this document.

    [root@nuc-router intel-nuc-router]# ./bwshaping.sh 
    Using external interface: eno1 with address 10.136.40.177/24
    Using internal interface: enp0s20f0u4 with address 192.168.96.1/24

    Usage: bandwidth-shaping.sh {start|stop|restart|show}

    [root@nuc-router intel-nuc-router]# ./bwshaping.sh start
    Using external interface: eno1 with address 10.136.40.177/24
    Using internal interface: enp0s20f0u4 with address 192.168.96.1/24

    Traffic shaping bandwidth can be specified as:
      kbps: Kilobytes per second
      mbps: Megabytes per second
      kbit: Kilobits per second
      mbit: Megabits per second
      bps: Bytes per second

    Specify upload bandwidth: 8mbit
    Specify download bandwidth: 1mbit

    Traffic shaping rules configured

    [root@nuc-router intel-nuc-router]# ./bwshaping.sh show
    Using external interface: eno1 with address 10.136.40.177/24
    Using internal interface: enp0s20f0u4 with address 192.168.96.1/24

    Bandwidth shaping rules for external interface: eno1
    qdisc htb 1: root refcnt 2 r2q 10 default 30 direct_packets_stat 0
     Sent 2110 bytes 17 pkt (dropped 0, overlimits 0 requeues 0) 
     backlog 0b 0p requeues 0 

    Bandwidth shaping rules for external interface: enp0s20f0u4
    qdisc htb 1: root refcnt 2 r2q 10 default 30 direct_packets_stat 0
     Sent 0 bytes 0 pkt (dropped 0, overlimits 0 requeues 0) 
     backlog 0b 0p requeues 0 

    [root@nuc-router intel-nuc-router]# ./bwshaping.sh stop
    Using external interface: eno1 with address 10.136.40.177/24
    Using internal interface: enp0s20f0u4 with address 192.168.96.1/24

    Stopping bandwidth shaping: done

The effects of bandwidth management can be demonstrated by using network performance/throughput testing sites, of which the location below is one example:

http://www.speedtest.net

Throughput should be seen to change from clients (connected behind/through the router) before/after setting limits using the script.

### IPTABLES Rule Management

The private/internal network behind the NUC can be (effectively) disconnected from the Internet (and the upstream network environment) by flushing the IPTABLES rules. This removes the IP NAT masquerading rule necessary for clients behind the router to obtain network service. A script has been provided to flush the rules, and also re-instate the NAT process. In some cases, third party utilities can interfere with IPTABLES, which might break the routing functions of the NUC. The iptables.sh script can be used to get those rules back into working condition.

    [root@nuc-router intel-nuc-router]# ./iptables.sh 
    Configuring IPTABLES ruleset
    Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: f

    Flushing all existing IPTABLES rules
    If acting as a router, this will stop NAT processing across interfaces
    NOTE: This will effectively break routing for the internal/private network

    [root@nuc-router intel-nuc-router]# ./iptables.sh 
    Configuring IPTABLES ruleset
    Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: l
    Listing all IPTABLES rules
    Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
     pkts bytes target     prot opt in     out     source               destination         

    Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
     pkts bytes target     prot opt in     out     source               destination         

    Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
     pkts bytes target     prot opt in     out     source               destination         

    Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
     pkts bytes target     prot opt in     out     source               destination         

    [root@nuc-router intel-nuc-router]# ./iptables.sh 
    Configuring IPTABLES ruleset
    Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: m
    Enabling IP NAT masquerading
    Internal network: enp0s20f0u4 192.168.96.1 192.168.96.0/24
    External network: eno1 10.136.40.177 10.136.40.0/24
    Enabling IP masquerading on outside interface
    Saving IPTABLES state to startup configuration
    iptables: Saving firewall rules to /etc/sysconfig/iptables:[  OK  ]

    [root@nuc-router intel-nuc-router]# ./iptables.sh 
    Configuring IPTABLES ruleset
    Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: s
    Saving IPTABLES state to startup configuration
    iptables: Saving firewall rules to /etc/sysconfig/iptables:[  OK  ]

### IPTABLES and Traffic Interception/Redirection to NGINX

Choosing the "intercept" option from the iptables.sh script will configure IPTABLES and NGINX for stream caching. In this scenario, IPTABLES intercepts HTTP requests to specific servers by matching their IP address(es), rewriting the packet headers and redirecting traffic to NGINX running locally. In the standard setup, we have NGINX configured with a caching component running/listening on port 3129. This component has to have a very specific setup. We need to ensure that MPEG-DASH stream metadata description files do not get served from cache, as stale file can cause problems that break playback. However, movie/video chunks need to be aggressively cached. Also, it is critical that NGINX does not receive unintended web traffic, otherwise it could return 404 errors for content. For that reason, the IPTABLES rules must be specific and concise.

The caching of content served from Akamai is also a special case. The Akamai domain needs to be added to the NGINX configuration file and then also the IP address of the Akamai CDN nodes added to the IPTABLES configuration. The iptables.sh script has automated most of this process, but there are some caveats. Any given Akamai URL normally resolves to two IP Addresses. However, those IP addresses can change over time and are almost always location specific. If attempting to cache Akamai content in a production context, it is critical to keep a close eye on what IP addresses Akamai is returning at any given time. The list of IP addresses needs to be comprehensive, otherwise you will fail to get the required bandwidth savings from traffic interception. These details are requirements due to the way Akamai's CND works, redirecting you to various different distribution nodes which could be located on different parts of their network. You can be given different IP addresses in the DNS response for their domain name.

Here is an example of the script output when configuring interception/redirection:

    [root@nuc-router intel-nuc-router]# ./iptables.sh 
    Configuring IPTABLES ruleset
    Choose [f]lush, [l]ist, [m]asquerade, [i]ntercept or [s]ave: i
    Building IPTABLES rules for TCP/80 -> local TCP/3129 traffic redirection
    Internal network: enp0s20f0u4 192.168.96.1 192.168.96.0/24
    External network: eno1 10.136.40.177 10.136.40.0/24
    WARNING:  Flushing all existing IPTABLES rules
    Attempt to add Akamai rule to NGINX configuration?
    Enter [y/n]: y
    Sample Akamai domain name: http://ozolive-i.akamaihd.net
    Domain must include protocol prefix (e.g. http://) but no path suffix
    Enter Akamai domain to cache: http://ozolive-i.akamaihd.net
    Added NGINX configuration for Akamai distribution
    Attempting to resolve the Akamai domain to the source/origin servers
    Note: These IP addresses will need to be manually entered below
    This is because IPTABLES cannot perform interception based on domains/names
    ozolive-i.akamaihd.net is an alias for a276.w23.akamai.net.
    a276.w23.akamai.net has address 216.206.30.10
    a276.w23.akamai.net has address 216.206.30.18
    Enter source/origin IP address to be intercepted and redirected
    IP address: 216.206.30.10
    Creating IPTABLES rule for 216.206.30.10
    Created IPTABLES rule successfully
    Attempt to add another rule to IPTABLES?
    Enter [y/n]: y
    Enter source/origin IP address to be intercepted and redirected
    IP address: 216.206.30.18
    Creating IPTABLES rule for 216.206.30.18
    Created IPTABLES rule successfully
    Attempt to add another rule to IPTABLES?
    Enter [y/n]: n
    Adding closing rules/statements
    Copying updated NGINX redirect/intercept configuration to server
    Reloading NGINX configuration
    IPTABLES rules saved successfully for reboot persistence

Also, for reference purposes, a sample NGINX configuration file generated by the iptables.sh script has been provided below. When the iptables.sh script is run, not only are IPTABLES rules created and saved, an NGINX configuration file is created and copied to the appropriate place on the system, then the command to reload NGINX is invoked. No further work should be needed for redirection to be active; the script performs and automates all the required steps.

    # NOTE: redirecting traffic not located at the origin servers below
    #  will result in the NGINX server returning 404 errors to clients!
    # It is CRITICAL that traffic interception rules only redirect appropriate traffic
    
    proxy_cache_path /home/nginx levels=1:2 keys_zone=my_cache:10m max_size=10g inactive=120m;
    
    server {
    
        #listen *:3129;
        listen [::]:3129 ipv6only=off;
    
        location ~* ^\/.*\.mpd$ {
        proxy_pass http://ozolive-i.akamaihd.net;
        add_header X-Proxy-Cache $upstream_cache_status; }
    
        location ~* ^\/.*\.(m4s|mp4|m4v)$ {
        proxy_cache my_cache;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        proxy_cache_valid any 120m;
        add_header X-Proxy-Cache $upstream_cache_status;
        proxy_pass http://ozolive-i.akamaihd.net;
        proxy_cache_key $request_uri;
        proxy_cache_lock on; }
    
        location ~* ^\/.*\.mpd$ {
        proxy_pass http://216.206.30.10;
        add_header X-Proxy-Cache $upstream_cache_status; }
    
        location ~* ^\/.*\.(m4s|mp4|m4v)$ {
        proxy_cache my_cache;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        proxy_cache_valid any 120m;
        add_header X-Proxy-Cache $upstream_cache_status;
        proxy_pass http://216.206.30.10;
        proxy_cache_key $request_uri;
        proxy_cache_lock on; }
    
        location ~* ^\/.*\.mpd$ {
        proxy_pass http://216.206.30.18;
        add_header X-Proxy-Cache $upstream_cache_status; }
    
        location ~* ^\/.*\.(m4s|mp4|m4v)$ {
        proxy_cache my_cache;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        proxy_cache_valid any 120m;
        add_header X-Proxy-Cache $upstream_cache_status;
        proxy_pass http://216.206.30.18;
        proxy_cache_key $request_uri;
        proxy_cache_lock on; }
    
    }

### Traffic Monitoring

Two utilities have been provided for traffic monitoring:

* nload
* iftop

We will briefly discuss the features of these two tools.

#### nload

The "nload" tool provides general throughput data and is most useful for monitoring how much traffic is passing through the upstream/external network interface (effectively measuring the utilisation of the NUC's Internet/network connections.

    [root@nuc-router intel-nuc-router]# ./monitoring.sh 
    Monitor interface traffic throughput
    Detected network interfaces:
    Internal: enp0s20f0u4
    External: eno1
    Choose [i]nternal, [e]xternal, or [o]ther interface: e
    Choose [n]load or [i]ftop: n

Typical output look like this:

    Device eno1 [10.136.40.177] (1/1):
    ================================================================================
    Incoming:





                                                           Curr: 5.04 kBit/s
                                                           Avg: 5.10 kBit/s
                                                           Min: 5.03 kBit/s
                                                           Max: 5.88 kBit/s
                                                           Ttl: 94.47 MByte
    Outgoing:





                                                           Curr: 1.97 kBit/s
                                                           Avg: 1.95 kBit/s
                                                           Min: 1.45 kBit/s
                                                           Max: 1.97 kBit/s
                                                           Ttl: 8.63 MByte


#### iftop

The "iftop" utility is particularly useful for monitoring the bandwidth being used by individual internal clients, and as such is usually run on the NUC's internal network interface.

    [root@nuc-router intel-nuc-router]# ./monitoring.sh 
    Monitor interface traffic throughput
    Detected network interfaces:
    Internal: enp0s20f0u4
    External: eno1
    Choose [i]nternal, [e]xternal, or [o]ther interface: i
    Choose [n]load or [i]ftop: i
    Note: The IFTOP utility requires root permissions
    interface: enp0s20f0u4
    IP address is: 192.168.96.1
    MAC address is: 8c:ae:4c:f4:2c:bc

Typical output looks like:

                    12.5Kb          25.0Kb          37.5Kb          50.0Kb    62.5Kb
    └───────────────┴───────────────┴───────────────┴───────────────┴───────────────


















    ────────────────────────────────────────────────────────────────────────────────
    TX:             cum:	  0B    peak:	   0b   rates:      0b      0b      0b
    RX:                       0B               0b               0b      0b      0b
    TOTAL:                    0B               0b               0b      0b      0b 

### Wi-Fi Access Point

You can have the NUC behave as a wireless access-point by running the provided script:

    ./wifi-ap.sh

This will create an SSID/network called:

    NUC-Router

The default passphrase is the same as the network name.
