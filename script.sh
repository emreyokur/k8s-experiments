ROOT_DIR=/root
SERVER_0=192.168.7.110
SERVER_1=192.168.7.111
SERVER_2=192.168.7.109
SERVER_3=192.168.7.112
WORK_DIR=/home
CLUSTER_NAME="case-emre-yuksel-okur"
CLUSTER_DOMAIN="abc"
CLUSTER_FQDN="$CLUSTER_NAME.$CLUSTER_DOMAIN"

ssh-keygen -t rsa -N '' -f $ROOT_DIR/.ssh/id_rsa <<< y
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_1
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_2
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_3

git clone https://github.com/kubernetes-sigs/kubespray.git

cd $WORK_DIR/kubespray

sudo pip3 install -r requirements.txt
sudo pip3 install -r contrib/inventory_builder/requirements.txt

cp -rfp inventory/sample inventory/$CLUSTER_NAME
declare -a IPS=($SERVER_0 $SERVER_1)
CONFIG_FILE=inventory/emre-cluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

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

helm repo add longhorn https://charts.longhorn.io
helm repo update
kubectl create namespace longhorn-system
helm install longhorn longhorn/longhorn --namespace longhorn-system


#Add Label to Node1
kubectl label nodes node1 dedicated=prometheus
kubectl taint nodes node1 dedicated=prometheus:NoSchedule

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm pull prometheus-community/kube-prometheus-stack --untar

##Disable dependencies
yq eval '.kubeStateMetrics.enabled = false' -i kube-prometheus-stack/values.yaml
yq eval '.grafana.enabled = false' -i kube-prometheus-stack/values.yaml
yq eval '.nodeExporter.enabled = false' -i kube-prometheus-stack/values.yaml
yq eval '.alertmanager.enabled = false' -i kube-prometheus-stack/values.yaml







