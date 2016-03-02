#!/bin/bash -e

: ${MACHINE_STORAGE_PATH?required}

for m in $(docker-machine ls -q | sort -r | egrep -v '[.]node[.]'); do
    docker-machine ssh ${m} '
        set -x;
        apt-get purge --auto-remove docker-engine -y;
        rm -rvf /etc/consul \
                /etc/default/docker \
                /etc/docker \
                /etc/systemd/system/docker.service \
                /var/lib/docker \
                /var/run/docker;
        rm -vf /etc/resolv.conf;
        resolvconf -u;
        ln -vrs /run/resolvconf/resolv.conf /etc/resolv.conf
    '
    rm -rvf ${MACHINE_STORAGE_PATH}/machines/${m}
done