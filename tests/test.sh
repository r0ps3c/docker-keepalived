#!/bin/sh -e

function timeout_handler {
    exit 1
}

trap timeout_handler SIGALRM

/usr/sbin/keepalived -l -n &

# timeout after 1m
(
    sleep 60; kill -ALRM $$
) &

while [ -z "$(ip -o addr show dev eth0 scope global to 192.168.200.1)" ]
do
    sleep 1
done

