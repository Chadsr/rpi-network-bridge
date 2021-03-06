#!/bin/bash

IPT=/sbin/iptables

function get_address() {
  addr=$(ifconfig $1 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1)
  echo "$addr"
}

function print_timestamp() {
  date "+%s"
}

echo "ATTENTION: This script needs to be run with root privileges (sudo $0)"
echo

echo "Enter the network interface which has Internet connection to forward. (e.g. wlan0): "
read inet_iface
echo

echo "Enter the local network interface you wish to forward to. (e.g. eth0): "
read local_iface
echo

inet_addr=$(get_address $inet_iface)
local_addr=$(get_address $local_iface)

echo "Internet address is:" $inet_addr "(Doesn't matter if this is dynamic)"
echo "Local address is: "$local_addr "(This should be the static IP you assigned!)"
echo "If the above addresses look incorrect, something is wrong with the interfaces you specified above. (or ifconfig is broken)"
echo

# Lease time for IP addresses
echo "Enter a IP lease time for the DHCP server (e.g. 12h): "
read dhcp_lease_time
echo

# trim the last octave of the local ip for example ranges
base_ip=`echo $local_addr | cut -d"." -f1-3`

echo "Enter a starting IP for the DHCP server to assign from. (e.g. $base_ip.50): "
read start_ip
echo
echo "Enter a end IP for the DHCP server to assign to. (e.g. $base_ip.150): "
read end_ip
echo

DNSMASQ_CONF="
interface=$local_iface
listen-address=$local_addr # Listen on local (non internet address)
bind-interfaces      # Bind to the interface to make sure we arent sending things elsewhere
server=8.8.8.8       # Forward DNS requests to Google DNS
server=8.8.4.4       # Forward DNS requests to Google DNS
no-poll
no-resolv
domain-needed        # Dont forward short names
bogus-priv           # Never forward addresses in the non-routed address spaces.
dhcp-range=$start_ip,$end_ip,$dhcp_lease_time
"

# make a backup of the previous dnsmasq.conf
echo "sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.old."print_timestamp
echo "Created backup of dnsmasq.conf"

# Write the newly generated config to the file
echo "$DNSMASQ_CONF" | sudo tee /etc/dnsmasq.conf > /dev/null
echo "New dnsmasq.conf written to /etc/dnsmasq.conf"

# Uncomment net.ipv4.ip_fo0rward=1, if commented out
sudo sed -i '/^#.* net.ipv4.ip_forward=1 /s/^#//' /etc/sysctl.conf
echo "Uncommented net.ipv4.ip_forward=1 in /etc/sysctl.conf (If it wasn't already)"

# iptables
echo
echo "Generating iptables"

# Flush the tables
$IPT -F INPUT
$IPT -F OUTPUT
$IPT -F FORWARD

$IPT -t nat -P PREROUTING ACCEPT
$IPT -t nat -P POSTROUTING ACCEPT
$IPT -t nat -P OUTPUT ACCEPT

# Allow forwarding packets:
$IPT -A FORWARD -p ALL -i $local_iface -j ACCEPT
$IPT -A FORWARD -i $inet_iface -m state --state ESTABLISHED,RELATED -j ACCEPT

# Packet masquerading
$IPT -t nat -A POSTROUTING -o $inet_iface -j SNAT --to-source $inet_addr

# Persistence
iptables-save | sudo tee /etc/iptables.ipv4.nat > /dev/null

# Create hook
echo 'iptables-restore < /etc/iptables.ipv4.nat' | sudo tee /lib/dhcpcd/dhcpcd-hooks/70-ipv4-nat > /dev/null

sysctl --system
