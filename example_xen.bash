#!/bin/bash

set -eu

function print_usage_and_die()
{
cat >&2 << EOF
usage: $0 XENSERVER_IP XENSERVER_PASSWORD

Setup OpenStack

positional arguments:
 XENSERVER_IP         IP address of the XenServer
 XENSERVER_PASSWORD   Password for your XenServer
EOF
exit 1
}

XENSERVER_IP="${1-$(print_usage_and_die)}"
XENSERVER_PASSWORD="${2-$(print_usage_and_die)}"

export GROUP_TYPE=xenserver
export DISTRO_NAME=fedora

rake kytoon:create \
    GROUP_CONFIG="config/server_group_xen.json" \
    GATEWAY_IP="$XENSERVER_IP"

export SERVER_NAME="login"

rake build_misc
rake build:packages # see config/packages

rake create_package_repo

# Copy hosts file to each node
rake ssh bash <<-"EOF_COPY_HOSTS"
for IP in $(cat /etc/hosts | cut -f 1); do
[[ "$IP" != "127.0.0.1" ]] && scp /etc/hosts $IP:/etc/hosts
done
EOF_COPY_HOSTS

rake fedora:create_rpm_repo
rake xen:install_plugins SOURCE_URL="git://github.com/openstack/nova.git"

CONFIGURATION="xen"
# FIXME: need to figure out how to make xenbr1 a XenServer management
# interface.  For now we replace XENAPI_CONNECTION_URL with the IP of xenbr0
XENBR0_IP=$(
    rake ssh \
        'ip a | grep xenbr0 | grep inet | sed -e "s|.*inet \([^/]*\).*|\1|"')
sed \
    -e "s|XENAPI_CONNECTION_URL|http://$XENBR0_IP|g" \
    -e "s|fixme|$XENSERVER_PASSWORD|g" \
    -i config/puppet-configs/$CONFIGURATION/nova1.pp

unset SERVER_NAME
rake puppet:install \
    SOURCE_URL="git://github.com/redhat-openstack/openstack-puppet.git" \
    PUPPET_CONFIG="$CONFIGURATION" || { echo "puppet failed."; exit 1; }

#reserve the first 5 IPs for the server group
rake ssh bash <<-"EOF_RESERVE_IPS"
ssh nova1 bash <<-"EOF_NOVA1"
for NUM in {0..5}; do
nova-manage fixed reserve 192.168.0.$NUM
done
EOF_NOVA1
EOF_RESERVE_IPS

rake keystone:configure \
    SERVER_NAME=nova1 \
    CINDER_HOST=nova1 \
    GLANCE_HOST=nova1 \
    NOVA_HOST=nova1 \
    SWIFT_HOST=nova1 \
    KEYSTONE_HOST=nova1

rake glance:load_images_xen SERVER_NAME=nova1
