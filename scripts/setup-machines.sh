#!/bin/bash -e

: ${MACHINE_STORAGE_PATH?required}
: ${MACHINE_DRIVER:=digitalocean}

. ${MACHINE_STORAGE_PATH}/drivers/${MACHINE_DRIVER}.env

: ${MACHINE_CLUSTER_INTERFACE?required}

: ${MACHINE_DOMAIN:=example.com}

: ${MACHINE_BRIDGE_ADDRESS:=172.17.0.1}
: ${MACHINE_BRIDGE_INTERFACE:=docker0}

: ${MACHINE_COUNT:=${1:-7}}
: ${MACHINE_PREFIX:=doccur}

declare -a MACHINE_NAMES
declare -a MACHINE_CLUSTER_ADDRESSES
declare -a MACHINE_PUBLIC_ADDRESSES

for i in $(seq 1 ${MACHINE_COUNT}); do
    MACHINE_NAME="${MACHINE_PREFIX}${i}"
    MACHINE_NAMES+=(${MACHINE_NAME})
    MACHINE_NODE_NAME="${MACHINE_NAME}.node.${MACHINE_DOMAIN}"

    if [ ! -d ${MACHINE_STORAGE_PATH}/machines/${MACHINE_NODE_NAME} ]; then
        echo "### ${MACHINE_NODE_NAME} >>>"
        docker-machine ${MACHINE_OPTS} create --driver ${MACHINE_DRIVER} ${MACHINE_NODE_NAME} 2>&1 | while read line; do
            echo "# ${line}"
        done
        echo "### ${MACHINE_NODE_NAME} <<<"
    fi

    MACHINE_PUBLIC_ADDRESSES+=($(docker-machine inspect --format '{{.Driver.IPAddress}}' ${MACHINE_NODE_NAME}))
    MACHINE_CLUSTER_ADDRESSES+=($(docker-machine ${MACHINE_OPTS} ssh ${MACHINE_NODE_NAME} "echo \$(ip addr show ${MACHINE_CLUSTER_INTERFACE} | head -3) | sed -e 's/.*[:] \(.*\)[:] .* inet \([0-9]*[.][0-9]*[.][0-9]*[.][0-9]*\)[/].*/\2/g'"))
done

declare -x MACHINE_STORAGE_PATH MACHINE_DRIVER MACHINE_DOMAIN MACHINE_BRIDGE_ADDRESS MACHINE_BRIDGE_INTERFACE MACHINE_CLUSTER_INTERFACE MACHINE_NAMES MACHINE_CLUSTER_ADDRESSES MACHINE_PUBLIC_ADDRESSES
declare -p $(declare -p | egrep -v 'declare[ ][-][-][ ]' | awk '{print $3}' | sed -e 's/[=].*//g' | sort | egrep '^MACHINE')