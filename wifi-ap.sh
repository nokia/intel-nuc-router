#!/bin/bash

WIFI_DEV=wlp2s0
ETH_DEV=enp0s25

sudo yum -y install haveged iw hostapd
if [ ! -d create_ap ]
then
	sudo git clone https://github.com/oblique/create_ap
fi

cd create_ap; sudo make install
create_ap $WIFI_DEV $ETH_DEV Intel-NUC-Router Intel-NUC-Router
