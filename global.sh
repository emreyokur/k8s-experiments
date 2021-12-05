#!/usr/bin/bash -x
export ROOT_DIR=/root
export SERVER_0=192.168.7.110
export SERVER_1=192.168.7.111
export SERVER_2=192.168.7.109
export SERVER_3=192.168.7.112
export WORK_DIR=/home
export CLUSTER_NAME="case-emre-yuksel-okur"
export CLUSTER_DOMAIN="abc"
export CLUSTER_FQDN="$CLUSTER_NAME.$CLUSTER_DOMAIN"

ssh-keygen -t rsa -N '' -f $ROOT_DIR/.ssh/id_rsa <<< y
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_1
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_2
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_3
