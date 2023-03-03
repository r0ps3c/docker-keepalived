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

while [ ! -e /tmp/success ]
do
    sleep 1
done