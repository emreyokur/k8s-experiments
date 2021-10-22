#!/usr/bin/bash

set -x

. $(dirname $0)/global.sh

cd kubespray/
cp -rfp inventory/sample inventory/$CLUSTER_NAME
declare -a IPS=($SERVER_0 $SERVER_1)
CONFIG_FILE=inventory/$CLUSTER_NAME/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

#Change cluster name
sed -i "s/cluster_name: cluster.local/cluster_name: $CLUSTER_FQDN/g" inventory/$CLUSTER_NAME/group_vars/k8s_cluster/k8s-cluster.yml

# Change network plugin
sed -i 's/kube_network_plugin: calico/kube_network_plugin: flannel/g' inventory/$CLUSTER_NAME/group_vars/k8s_cluster/k8s-cluster.yml

# Install metric server
sed -i "s/metrics_server_enabled: false/metrics_server_enabled: true/g" inventory/$CLUSTER_NAME/group_vars/k8s_cluster/addons.yml

# Install helm
sed -i "s/helm_enabled: false/helm_enabled: true/g" inventory/$CLUSTER_NAME/group_vars/k8s_cluster/addons.yml

# Open read only port
sed -i "s/# kube_read_only_port:/kube_read_only_port:/g" inventory/$CLUSTER_NAME/group_vars/all/all.yml

# Check ansible connectivity to all nodes.
ansible -i inventory/$CLUSTER_NAME/hosts.yml -m ping all

ansible-playbook -i inventory/$CLUSTER_NAME/hosts.yml --become --become-user=root cluster.yml
