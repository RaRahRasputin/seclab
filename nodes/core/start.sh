# Assign gateway addresses
ip addr add 10.10.10.1/24 dev eth2.10
ip addr add 10.10.20.1/24 dev eth2.20
ip addr add 10.10.99.1/24 dev eth2.99

# Bring VLAN interfaces up
ip link set eth2.10 up
ip link set eth2.20 up
ip link set eth2.99 up

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# Enable OSPF
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
/usr/lib/frr/frrinit.sh start
vtysh -b

ip -br addr
ip route
