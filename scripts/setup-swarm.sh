#!/bin/bash -e

: ${MACHINE_STORAGE_PATH?required}

MTEMP=$(mktemp)
${MACHINE_STORAGE_PATH}/scripts/setup-machines.sh > ${MTEMP}
. ${MTEMP}

: ${MACHINE_DATACENTER?required}

docker_machine_recreate() {
    MACHINE_TYPE=${1?required}

    [ ${MACHINE_TYPE} = 'server' ] && local MACHINE_CREATE_OPTS="${MACHINE_CREATE_OPTS}
        --swarm-master
        --swarm-opt replication
        --swarm-opt advertise=${MACHINE_CLUSTER_PARTICIPANT_ADDRESS}:3376
    "

    : ${MACHINE_NAME?required}
    : ${MACHINE_DOMAIN?required}
    : ${MACHINE_SSH_KEY?required}
    : ${MACHINE_SSH_USER?required}
    : ${MACHINE_BRIDGE_ADDRESS?required}
    : ${MACHINE_BRIDGE_INTERFACE?required}
    : ${MACHINE_CLUSTER_CONSUL:="consul.service.${MACHINE_DOMAIN}:8500"}
    : ${MACHINE_CLUSTER_INTERFACE?required}
    : ${MACHINE_CLUSTER_PARTICIPANT_ADDRESS?required}
    : ${MACHINE_CLUSTER_REPLICANT_ADDRESS_0?required}
    : ${MACHINE_CLUSTER_REPLICANT_ADDRESS_1?required}
    : ${MACHINE_CLUSTER_REPLICANT_ADDRESS_2?required}

    export MACHINE_CLUSTER_CONSUL="consul.service.${MACHINE_DOMAIN}:8500"
    export MACHINE_PATH="${MACHINE_STORAGE_PATH}/machines/${MACHINE_NAME}"
    export MACHINE_DATE="$(date '+%Y%m%d-%H%M%S')"

    echo "### ${MACHINE_NAME} (MACHINE_*) >>>"
    declare -p $(declare -p | egrep -v 'declare[ ][-][-][ ]' | awk '{print $3}' | sed -e 's/[=].*//g' | sort | egrep '^MACHINE') | sed -e 's/^/# /g'
    echo "### ${MACHINE_NAME} (MACHINE_*) <<<"

    if [ ! -d ${MACHINE_PATH} ]; then
        docker-machine ${MACHINE_OPTS} create --driver generic \
            --engine-opt "cluster-advertise ${MACHINE_CLUSTER_INTERFACE}:2376" \
            --engine-opt "cluster-store consul://${MACHINE_CLUSTER_CONSUL}" \
            --engine-opt "dns ${MACHINE_CLUSTER_PARTICIPANT_ADDRESS}" \
            --engine-opt "dns-search ${MACHINE_DOMAIN}" \
            --engine-opt "log-driver json-file" \
            --engine-opt "log-opt max-file=10" \
            --engine-opt "log-opt max-size=10m" \
            --generic-ip-address ${MACHINE_PUBLIC_ADDRESS} \
            --generic-ssh-key ${MACHINE_SSH_KEY} \
            --generic-ssh-user ${MACHINE_SSH_USER} \
            --swarm \
            --swarm-discovery "consul://${MACHINE_CLUSTER_CONSUL}" \
            --tls-san ${MACHINE_NODE_NAME} \
            --tls-san ${MACHINE_CLUSTER_PARTICIPANT_ADDRESS} \
            --tls-san ${MACHINE_PUBLIC_ADDRESS} \
            ${MACHINE_CREATE_OPTS} \
        ${MACHINE_NAME} 2>&1 | while read line; do
            echo "# ${line}"
        done
    fi

    echo "### ${MACHINE_NAME} (backup consul config) >>>"
    docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NAME} "[ -d /etc/consul ] && sudo mv -vf /etc/consul /etc/consul.${MACHINE_DATE}; sudo rm -rvf /tmp/consul" 2>&1 | while read line; do
        echo "# ${line}"
    done
    echo "### ${MACHINE_NAME} (backup consul config) <<<"

    echo "### ${MACHINE_NAME} (upload consul config) >>>"
    docker-machine ${MACHINE_OPTS} scp -r ${MACHINE_STORAGE_PATH}/compose/consul/config ${MACHINE_NAME}:/tmp/consul 2>&1 | while read line; do
        echo "# ${line}"
    done
    echo "### ${MACHINE_NAME} (upload consul config) <<<"

    echo "### ${MACHINE_NAME} (install consul config) >>>"
    docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NAME} "sudo mv -vf /tmp/consul /etc" 2>&1 | while read line; do
        echo "# ${line}"
    done
    echo "### ${MACHINE_NAME} (install consul config) <<<"

    eval $(docker-machine env ${MACHINE_NAME})

    echo "### ${MACHINE_NAME} (DOCKER_*) >>>"
    declare -p $(declare -p | egrep -v 'declare[ ][-][-][ ]' | awk '{print $3}' | sed -e 's/[=].*//g' | sort | egrep '^DOCKER') | sed -e 's/^/# /g'
    echo "### ${MACHINE_NAME} (DOCKER_*) <<<"

    echo "### ${MACHINE_NAME} (docker-compose -f ${MACHINE_TYPE}.yml) >>>"
    docker-compose -f ${MACHINE_STORAGE_PATH}/compose/consul/${MACHINE_TYPE}.yml up -d
    echo "### ${MACHINE_NAME} (docker-compose -f ${MACHINE_TYPE}.yml) <<<"

    eval $(docker-machine env --unset)

    echo "### ${MACHINE_NAME} (replace /etc/resolv.conf) >>>"
    docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NAME} "sudo rm /etc/resolv.conf" 2>&1 | while read line; do
        echo "# ${line}"
    done
    docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NAME} "echo 'nameserver ${MACHINE_CLUSTER_PARTICIPANT_ADDRESS}' | sudo tee /etc/resolv.conf" 2>&1 | while read line; do
        echo "# ${line}"
    done
    echo "### ${MACHINE_NAME} (replace /etc/resolv.conf) <<<"

    echo "### ${MACHINE_NAME} (restart docker) >>>"
    docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NAME} "sudo systemctl restart docker || sudo service docker restart" 2>&1 | while read line; do
        echo "# ${line}"
    done
    echo "### ${MACHINE_NAME} (restart docker) <<<"
}

for i in $(seq 0 $((${#MACHINE_NAMES[*]}-1))); do
    export MACHINE_NAME=${MACHINE_NAMES[${i}]}
    export MACHINE_NODE_NAME="${MACHINE_NAME}.node.${MACHINE_DOMAIN}"
    export MACHINE_PUBLIC_ADDRESS=${MACHINE_PUBLIC_ADDRESSES[${i}]}
    export MACHINE_CLUSTER_PARTICIPANT_ADDRESS=${MACHINE_CLUSTER_ADDRESSES[${i}]}

    if [ -f ${MACHINE_STORAGE_PATH}/machines/${MACHINE_NODE_NAME}/id_rsa ]; then
        export MACHINE_SSH_KEY="${MACHINE_STORAGE_PATH}/machines/${MACHINE_NODE_NAME}/id_rsa"
    elif [ -f ${HOME}/.ssh/id_rsa ]; then
        export MACHINE_SSH_KEY="${HOME}/.ssh/id_rsa"
    fi

    if [ ${i} -eq 1 ]; then
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_0=${MACHINE_CLUSTER_ADDRESSES[1]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_1=${MACHINE_CLUSTER_ADDRESSES[0]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_2=${MACHINE_CLUSTER_ADDRESSES[2]}
    elif [ ${i} -eq 2 ]; then
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_0=${MACHINE_CLUSTER_ADDRESSES[2]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_1=${MACHINE_CLUSTER_ADDRESSES[0]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_2=${MACHINE_CLUSTER_ADDRESSES[1]}
    else
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_0=${MACHINE_CLUSTER_ADDRESSES[0]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_1=${MACHINE_CLUSTER_ADDRESSES[1]}
        export MACHINE_CLUSTER_REPLICANT_ADDRESS_2=${MACHINE_CLUSTER_ADDRESSES[2]}
    fi

    if   [ ${i} -lt 3 ]; then
        docker_machine_recreate 'server'
    else
        docker_machine_recreate 'agent'
    fi

done