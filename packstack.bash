export GROUP_TYPE=libvirt
export DISTRO_NAME=centos
rake kytoon:create GROUP_CONFIG="config/server_group.json"


# required for Torpedo
#rake build_misc
#rake torpedo:build_packages
#rake build_packstack --trace
rake rhel:build_packstack --trace

#rake create_package_repo

