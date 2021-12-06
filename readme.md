## Readme

This document aims to create an enterprise level kubernetes environment including monitoring, service discovery, log aggregation, ci&cd pipelines and admissioning features.

Below you can find the installation steps and related documentation for each step. 

## Contents

 1. [ Kubespray ](#kubespray)
 2. [Bare-Metal Kubernetes w Kubespray](#k8s)
 3. [Prometheus on Kubernetes](#prometheus)
 4. [Ingress Deamonset Controller](#ingress)
 5. [Consul](#consul)
 6. [Federated Prometheus](#federated-prometheus)
 7. [Grafana](#grafana)
 8. [AlertManager](#alertmanager)
 9. [ElasticSearch & Kibana](#elk)
 10. [Gitlab](#gitlab)
 11. [A Sample Application Deployment w Gitlab Pipelines](#gitlab-example)
 12. [K8S Custom Validation & Admission Webhooks](#k8s-webhooks)

## Documentation

<a name="kubespray"></a>
### Kubespray

Kubespray is a composition of [Ansible](https://docs.ansible.com/) playbooks, [inventory](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ansible.md), provisioning tools, and domain knowledge for generic OS/Kubernetes clusters configuration management tasks.

##### Configuring environment
In this workshop, I had 4 centOS servers reserved.  In the code below, server ip's are configured and since kubespray needs to connect other nodes, I have configured the ssh authentication. 

```shell
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
```

#### Installing Kubespray

Installing Kubespray is pretty straightforward. Once git repository is cloned, the first thing to do is to install kubespray requirements such as ansible, jinja etc.

```shell
git clone https://github.com/kubernetes-sigs/kubespray.git

cd $WORK_DIR/kubespray

sudo pip3 install -r requirements.txt
sudo pip3 install -r contrib/inventory_builder/requirements.txt
```

<a name="k8s"></a>
### Bare-Metal Kubernetes w Kubespray

After installing kubespray & its requirements, we can proceed to kubernetes configuration. Server inventory should be configured for kubernetes master and worker nodes. Here, we can use kubespray's inventory builder.

```shell
cp -rfp inventory/sample inventory/$CLUSTER_NAME
declare -a IPS=($SERVER_0 $SERVER_1)
CONFIG_FILE=inventory/emre-cluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
```

After finished with the inventory. Some k8s specific configuration should be specified. These are specifying cluster name and network plugin. Also, kubespray comes with a variety of addons which you can enable, I have enabled helm and metric server to use them in the next steps.

```shell
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

```

And lastly, in ansible we trust! First, we can check the connectivity of ansible to the servers specified in the inventory file and if successful we can run the playbook. When finished successfully, your cluster will be up for the next steps. 

```shell
# Check ansible connectivity to all nodes.
ansible -i inventory/$CLUSTER_NAME/hosts.yml -m ping all

ansible-playbook -i inventory/$CLUSTER_NAME/hosts.yml --become --become-user=root cluster.yml
```

All above configurations and installation can be triggered by executing the scripts below.

[install-kubespray.sh](https://github.com/emreyokur/k8s-experiments/blob/main/install-kubespray.sh "install-kubespray.sh")
[install-kubernetes.sh](https://github.com/emreyokur/k8s-experiments/blob/main/install-kubernetes.sh "install-kubernetes.sh")

<a name="prometheus"></a>
### Prometheus on Kubernetes

In this step, we are going to install a prometheus to gather kubernetes metrics. As mentioned in the previous step, we are going to use helm for k8s deployment. Helm pretty much eases the configuration and installation processes, also eases release management, upgrading or rollback scenarios. 

For prometheus to store its data on kubernetes, a persistent volume & pv claim should be configured in the k8s environment. In /prometheus folder, you can find the manifest files for both pv & pvc. You can apply these with kubectl apply command. 

###### Persistent Volume
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-volume
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
```

######Persistent Volume Claim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-volume-claim
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```
##### Dedicate Node for Prometheus
Here, in this scenario, we want our prometheus to be deployed onto node2, and in addition to this we do not want any other deployment to be deployed to node2, except prometheus. Briefly, node2 should only be allocated for prometheus. To apply these prerequisites, I tainted node1 and applied the taint toleration in the helm values file of prometheus.

```bash
kubectl taint nodes node2 dedicated=prometheus:NoSchedule
```

List the taint applied.
```bash
kubectl get nodes/node2 -o json | jq '.spec.taints'
[
  {
    "effect": "NoSchedule",
    "key": "dedicated",
    "value": "prometheus"
  }
]
```

```yaml
  tolerations: 
    - key: "dedicated"
      operator: "Equal"
      value: "prometheus"
      effect: "NoSchedule"
```

We can also label the node and set pod affinity for prometheus deployment. We can use "requiredDuringSchedulingIgnoredDuringExecution" expression for prometheus to be deployed onto dedicated node.

```bash
kubectl label nodes node2 dedicated=prometheus
```

```yaml
affinity: 
    nodeAffinity: 
      requiredDuringSchedulingIgnoredDuringExecution: 
        nodeSelectorTerms: 
        - matchExpressions: 
          - key: dedicated
            operator: In
            values:
            - prometheus
```

###### Configuring the helm values file for prometheus installation. 

I have installed prometheus server for storing time series data, before installation I have edited values file to configure tolerations and affinity, persistent volumes and also configured to use hostnetwork and created prometheus ClusterIP service and ingress. I also enabled and installed node-exporter and kube-state-metrics to gather metrics and send it to prometheus. Node exporter should be installed as a daemonset to be deployed onto all nodes.

```yaml
kubeStateMetrics:
  ## If false, kube-state-metrics sub-chart will not be installed
  ##
  enabled: true

nodeExporter:
  ## If false, node-exporter will not be installed
  ##
  enabled: true
```

After all, running the install-prometheus.sh will trigger the installation. 

```bash
#!/usr/bin/bash
set -x
kubectl label nodes node2 dedicated=prometheus
kubectl apply -f create-pv.yaml
kubectl apply -f create-pvc.yaml
chmod 777 /mnt/data
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/prometheus --values prometheus/values.yaml
```

<a name="ingress"></a>
### Ingress Deamonset Controller

Ingress Controller installation is also straightforward. I again used ingress-nginx helm chart to deploy it. Since we are installing it to bare metal servers, we should enable hostNetwork configuration and since we want it to be installed to every node, we need to specify its kind as DaemonSet. 

To start with, I have created a dedicated namespace for ingress-nginx and proceed to deployment. 

```bash
#!/usr/bin/bash
set -x

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --values ingress/values.yaml -n ingress-nginx
```

<a name="consul"></a>
### Consul

Consul is a service networking solution to automate network configurations, discover services, and enable secure connectivity across any cloud or runtime.

Here, we use Consul for service discovery purposes. More clearly, we are going to use Consul for prometheus federation.

We are going to install a one node server mode Consul cluster, and then we are going to install consul agent to where internal prometheus resides. 

In the beginning, I had 4 servers, which I installed kubernetes master node to server1, worker node and prometheus to server2. Now, we are going to install consul server to server3. We will install it as a service. 

First we install consul repo to yum package repositories and install consul CLI. 

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install consul
```

Then, we create an encryption key for consul, which we are going to use it in configuration file.

```bash
export ENCRYPT=$(consul keygen)
```

Next, we create server and client certificates, also certificate authority file and distribute it to servers.

```bash
consul tls ca create
consul tls cert create -server -dc $DC

mkdir --parents /etc/consul.d
cp consul-agent-ca.pem $DC-server-consul-0-key.pem $DC-server-consul-0.pem /etc/consul.d/

for i in ${!AGENTS[@]}; do
  consul tls cert create -client -dc $DC
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$AGENTS[$i] mkdir --parents /etc/consul.d
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null consul-agent-ca.pem $DC-client-consul-$i-key.pem $DC-client-consul-$i.pem root@$AGENTS[$i]:/etc/consul.d/
done
```

Next, we can configure consul config file in hcl format. Here, you can see encryption key, ca and cert files. Since we are installing consul server, not the agent, we see server certificates here. Also, we want consul to have a ui, and we are enabling it in the server.hcl file.

```bash
cat > consul.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/consul"
encrypt = "$ENCRYPT"
ca_file = "/etc/consul.d/consul-agent-ca.pem"
cert_file = "/etc/consul.d/dc1-server-consul-0.pem"
key_file = "/etc/consul.d/dc1-server-consul-0-key.pem"
verify_incoming = true
verify_outgoing = true
verify_server_hostname = true
EOF

mv consul.hcl /etc/consul.d/

cat > server.hcl << EOF
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui = true
EOF

mv server.hcl /etc/consul.d/

chown --recursive consul:consul /etc/consul.d
```

After everything is configured, the rest is to systemctl service configurations. 

```bash
cat > consul.service << EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl
[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

mv consul.service /usr/lib/systemd/system/consul.service

consul validate /etc/consul.d/consul.hcl
systemctl enable consul
systemctl start consul
systemctl status consul
```

In the repository, install-consul-server.sh will do all the installation tasks above.

##### Consul Agent
Installation of consul agent is very similar to consul server. First we do not have a server.hcl and a few differences in the consul.hcl file;

retry_join = ["192.168.7.109"]
bind_addr = "192.168.7.110"
server = false

retry join ip address is the address of the consul server, in which agent needs to join. Bind address is the agent's ip address. Server mode should be false since this is agent installation. Other parts are pretty same with the server installation. You can trigger install-consul-agent.sh to complete configuration and installation. 

Finally, we needed to register prometheus to consul, so that we can do prometheus federation in the next step. To register prometheus to consul, we can put service description file to consul config directory. 

```json
{"service":
 { "name": "internal-prometheus", "port": 80, "check": {"args": [ "curl", "http://case-emreyukselokur.abc/-/healthy"], "interval": "10s"} }}
```
After restarting consul, we can see the prometheus service on consul ui. 

<a name="federated-prometheus"></a>
### Federated Prometheus

Now, we are going to install a master prometheus server outside Kubernetes. Install-prometheus-master.sh will do the installation as a service, but first we need to prepare configuration file which resides under /prometheus-master folder. The tricky point is the federate job configuration, which should be like below, to connect internal-prometheus via consul.

```yaml
- job_name: federate
    honor_labels: true
    metrics_path: '/federate'
    consul_sd_configs:
    - server: localhost:8500
      services:
        - internal-prometheus
```

<a name="grafana"></a>
### Grafana

After we see, kubernetes metrics are being stored on prometheus, to monitor these metrics, we need to install grafana. I decided to install it into kubernetes via helm chart.

I created another persistent volume, ClusterIP service and ingress for grafana. And I added prometheus as a datasource. 

```yaml
datasources: 
 datasources.yaml:
   apiVersion: 1
   datasources:
   - name: "Prometheus Master"
     type: prometheus
     url: http://192.168.7.109:9090
     access: proxy
     isDefault: true
```

We can install grafana using helm install command. I have used 
grafana                 https://grafana.github.io/helm-charts repository and used grafana-6.17.3 chart. 

When installation finished you can login to grafana ui via the url specified in the ingress configuration. You can login with admin account. Password is stored as a secret. To get the password, you can run the command below. 

```bash
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

After logged in, we can create a dashboard to view cluster metrics. There are dashboards provided by grafana labs. I have used https://grafana.com/api/dashboards/315/revisions/3/download this one, exported it as json and installed it via grafana ui to create the dashboard. 

<a name="alertmanager"></a>
### AlertManager

Alertmanager handles alerts sent by client applications such as the Prometheus server. It takes care of deduplicating, grouping, and routing them to the correct receiver integration such as email, PagerDuty, or OpsGenie. It also takes care of silencing and inhibition of alerts.

In our scenario, we are going to install it onto server3 and we are going to create email receivers. Alerts will come from prometheus, so we also need to configure Prometheus alert rules to direct alerts to alertmanager. 

Install-alertmanager.sh in the repository will install alertmanager. Below is the configuration for an email receiver. 

```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'AlertManager <alertmanager@case-emreyukselokur.abc>'
  smtp_auth_username: 'noreply.emreyokur@gmail.com'
  smtp_auth_identity: 'noreply.emreyokur@gmail.com'
  smtp_auth_password: '*****'

route:
  group_by: ['instance', 'alert']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: emre

receivers:
  - name: 'emre'
    email_configs:
      - to: 'emreyokur@gmail.com'

```

And below is the prometheus configs.

```yaml
rule_files:
  - alert.rules

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - 'localhost:9093'
```

Finally, below is the alert defined. It alerts when prometheus restarts more than once in 15 minutes. 

```yaml
groups:
- name: prometheus
  rules:
  - alert: PrometheusTooManyRestarts
    expr: increase(kube_pod_container_status_restarts_total{container="prometheus-server"}[15m]) > 1
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: Prometheus too many restarts
      description: "Prometheus has restarted more than once in the last 15 minutes. It might be crashlooping."

```

<a name="elk"></a>
### ElasticSearch & Kibana

Now, we have kubernetes cluster up, prometheus up and it is time to install elasticsearch and filebeat to aggregate pod logs into elasticsearch and view them on Kibana. 

To install ES, we need to first install JDK and then add elastic repositories for yum. 
Install-elasticsearch.sh will make these configurations and install it as a service. 

```bash
#!/usr/bin/bash

set -x

yum -y install java-openjdk-devel java-openjdk

cat > /etc/yum.repos.d/elasticsearch.repo << EOF
[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
yum clean all
yum makecache

yum -y install elasticsearch
systemctl enable --now elasticsearch.service 
curl http://127.0.0.1:9200
```

To direct kubernetes logs to elasticsearch and kibana, I install filebeat onto kubernetes. Below is the deployment manifest of filebeat, you can see the elasticsearch configuration too.  It directs all containers logs to elasticsearch.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: kube-system
  labels:
    k8s-app: filebeat
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
  labels:
    k8s-app: filebeat
rules:
- apiGroups: [""] # "" indicates the core API group
  resources:
  - namespaces
  - pods
  verbs:
  - get
  - watch
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: kube-system
  labels:
    k8s-app: filebeat
data:
  filebeat.yml: |-
    filebeat.config:
      prospectors:
        # Mounted `filebeat-prospectors` configmap:
        path: ${path.config}/prospectors.d/*.yml
        # Reload prospectors configs as they change:
        reload.enabled: true
      modules:
        path: ${path.config}/modules.d/*.yml
        # Reload module configs as they change:
        reload.enabled: true
    output: 
      elasticsearch:
        hosts: ['192.168.7.112:9200']
      logstash: 
        enabled: false
    setup: 
      kibana:
        host: "192.168.7.112:5601"
      dashboards: 
        enabled: true
      
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-prospectors
  namespace: kube-system
  labels:
    k8s-app: filebeat
data:
  kubernetes.yml: |-
    - type: docker
      containers.ids:
      - "*"
      processors:
        - add_kubernetes_metadata:
            in_cluster: true
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: kube-system
  labels:
    k8s-app: filebeat
spec:
  selector:
    matchLabels:
      k8s-app: filebeat
  template:
    metadata:
      labels:
        k8s-app: filebeat


    spec:
      tolerations:
      # this toleration is to have the daemonset runnable on master nodes
      # remove it if your masters can't run pods
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: "dedicated"
        operator: "Equal"
        value: "prometheus"
        effect: "NoSchedule"
      serviceAccountName: filebeat
      terminationGracePeriodSeconds: 30
      containers:
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:6.8.4
        args: [
          "-c", "/etc/filebeat.yml",
          "-e",
        ]
        env:
        - name: ELASTICSEARCH_HOST
          value: "192.168.7.112"
        - name: ELASTICSEARCH_PORT
          value: "9200"
        securityContext:
          runAsUser: 0
        volumeMounts:
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: prospectors
          mountPath: /usr/share/filebeat/prospectors.d
          readOnly: true
        - name: data
          mountPath: /usr/share/filebeat/data
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: config
        configMap:
          defaultMode: 0600
          name: filebeat-config
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: prospectors
        configMap:
          defaultMode: 0600
          name: filebeat-prospectors
      - name: data
        emptyDir: {}
```

Last, we need to install Kibana. We can again use yum to install it. In the config file, elasticsearch.url is enough for Kibana to get data from elasticsearch.

```bash
#!/usr/bin/bash

set -x

yum -y install kibana
cat > /etc/kibana/kibana.yml << EOF
server.host: "0.0.0.0"
server.name: "kibana.case-emreyukselokur.abc"
elasticsearch.url: "http://localhost:9200"
EOF

systemctl enable --now kibana
```

<a name="gitlab"></a>
### Gitlab

Now, we are going to use gitlab to create pipelines for our deployments. 
We first install gitlab-ee and then we should login to gitlab, create some repositories, install gitlab runners, configure their authentications to gitlab server, create pipelines and run them. 

For installation scripts, you can review install-gitlab.sh and install-gitlab-runner.sh

Now, to install prometheus over gitlab, below you can find the example pipeline file and related scripts.

```yaml
stages:
  - "install"

image: alpine

1.1-install:
  stage: install
  script: sh install-prometheus-master.sh

```

Codes can be found at: http://gitlab.case-emreyukselokur.abc/trendyol/prometheus

And for alertmanager;

```yaml
stages:
  - "download"
  - "config"
  - "service"
image: alpine

1.1-install-binaries:
  stage: download
  script: sh download.sh

2.1-configure:
  stage: config
  script: sh config.sh

3.1-service:
  stage: service
  script: sh service.sh

```
http://gitlab.case-emreyukselokur.abc/trendyol/alertmanager

<a name="gitlab-example"></a>
### A Sample Application Deployment w Gitlab Pipelines
For sample application deployment on Gitlab, I chose a pyhton flask app. I have created its dockerfile and helm chart to deploy it onto kubernetes. Also I created gitlab-pipelines file to run the deployment on Gitlab. 

The app is a simple app, its replica count is 2 and when accessed, it prints the pod name.

http://gitlab.case-emreyukselokur.abc/trendyol/hello-goose



<a name="k8s-webhooks"></a>
### K8S Custom Admission Controllers
An admission controller is a piece of code that intercepts requests to the Kubernetes API server prior to persistence of the object, but after the request is authenticated and authorized. 

There are two types of admission controllers, validating and mutating. Validating hooks reject or accept the object whereas mutating hooks can change the configuration of the object. 

In my case, the objective was to set the cpu max limit should be no more than 2 cores. 
I chose to proceed with OPA's (Open Policy Agent) GateKeeper for Kubernetes. https://open-policy-agent.github.io/gatekeeper/website/docs/ 

First I had to install opa gatekeeper to kubernetes. I used its helm chart. 
helm install gatekeeper/gatekeeper --generate-name

Then I created a CRD "ConstraintTemplate" which opa will use for constraints, and then created a constraint which will be used for my validating addmission hook. 

Here is the contraint template. OPA uses rego language to implement your rules, so an enterprise can create its own rules by writing rego rules and creating several rule templates. Below is an example which I used in this case. 

```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8scontainerlimits
  annotations:
    description: >-
      Requires containers to have memory and CPU limits set and constrains
      limits to be within the specified maximum values.
      https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
spec:
  crd:
    spec:
      names:
        kind: K8sContainerLimits
      validation:
        # Schema for the `parameters` field
        openAPIV3Schema:
          type: object
          properties:
            cpu:
              description: "The maximum allowed cpu limit on a Pod, exclusive."
              type: string
            memory:
              description: "The maximum allowed memory limit on a Pod, exclusive."
              type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8scontainerlimits
        missing(obj, field) = true {
          not obj[field]
        }
        missing(obj, field) = true {
          obj[field] == ""
        }
        canonify_cpu(orig) = new {
          is_number(orig)
          new := orig * 1000
        }
        canonify_cpu(orig) = new {
          not is_number(orig)
          endswith(orig, "m")
          new := to_number(replace(orig, "m", ""))
        }
        canonify_cpu(orig) = new {
          not is_number(orig)
          not endswith(orig, "m")
          re_match("^[0-9]+$", orig)
          new := to_number(orig) * 1000
        }
        # 10 ** 21
        mem_multiple("E") = 1000000000000000000000 { true }
        # 10 ** 18
        mem_multiple("P") = 1000000000000000000 { true }
        # 10 ** 15
        mem_multiple("T") = 1000000000000000 { true }
        # 10 ** 12
        mem_multiple("G") = 1000000000000 { true }
        # 10 ** 9
        mem_multiple("M") = 1000000000 { true }
        # 10 ** 6
        mem_multiple("k") = 1000000 { true }
        # 10 ** 3
        mem_multiple("") = 1000 { true }
        # Kubernetes accepts millibyte precision when it probably shouldn't.
        # https://github.com/kubernetes/kubernetes/issues/28741
        # 10 ** 0
        mem_multiple("m") = 1 { true }
        # 1000 * 2 ** 10
        mem_multiple("Ki") = 1024000 { true }
        # 1000 * 2 ** 20
        mem_multiple("Mi") = 1048576000 { true }
        # 1000 * 2 ** 30
        mem_multiple("Gi") = 1073741824000 { true }
        # 1000 * 2 ** 40
        mem_multiple("Ti") = 1099511627776000 { true }
        # 1000 * 2 ** 50
        mem_multiple("Pi") = 1125899906842624000 { true }
        # 1000 * 2 ** 60
        mem_multiple("Ei") = 1152921504606846976000 { true }
        get_suffix(mem) = suffix {
          not is_string(mem)
          suffix := ""
        }
        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 0
          suffix := substring(mem, count(mem) - 1, -1)
          mem_multiple(suffix)
        }
        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 1
          suffix := substring(mem, count(mem) - 2, -1)
          mem_multiple(suffix)
        }
        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) > 1
          not mem_multiple(substring(mem, count(mem) - 1, -1))
          not mem_multiple(substring(mem, count(mem) - 2, -1))
          suffix := ""
        }
        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) == 1
          not mem_multiple(substring(mem, count(mem) - 1, -1))
          suffix := ""
        }
        get_suffix(mem) = suffix {
          is_string(mem)
          count(mem) == 0
          suffix := ""
        }
        canonify_mem(orig) = new {
          is_number(orig)
          new := orig * 1000
        }
        canonify_mem(orig) = new {
          not is_number(orig)
          suffix := get_suffix(orig)
          raw := replace(orig, suffix, "")
          re_match("^[0-9]+$", raw)
          new := to_number(raw) * mem_multiple(suffix)
        }
        violation[{"msg": msg}] {
          general_violation[{"msg": msg, "field": "containers"}]
        }
        violation[{"msg": msg}] {
          general_violation[{"msg": msg, "field": "initContainers"}]
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          cpu_orig := container.resources.limits.cpu
          not canonify_cpu(cpu_orig)
          msg := sprintf("container <%v> cpu limit <%v> could not be parsed", [container.name, cpu_orig])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          mem_orig := container.resources.limits.memory
          not canonify_mem(mem_orig)
          msg := sprintf("container <%v> memory limit <%v> could not be parsed", [container.name, mem_orig])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not container.resources
          msg := sprintf("container <%v> has no resource limits", [container.name])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          not container.resources.limits
          msg := sprintf("container <%v> has no resource limits", [container.name])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          missing(container.resources.limits, "cpu")
          msg := sprintf("container <%v> has no cpu limit", [container.name])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          missing(container.resources.limits, "memory")
          msg := sprintf("container <%v> has no memory limit", [container.name])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          cpu_orig := container.resources.limits.cpu
          cpu := canonify_cpu(cpu_orig)
          max_cpu_orig := input.parameters.cpu
          max_cpu := canonify_cpu(max_cpu_orig)
          cpu > max_cpu
          msg := sprintf("container <%v> cpu limit <%v> is higher than the maximum allowed of <%v>", [container.name, cpu_orig, max_cpu_orig])
        }
        general_violation[{"msg": msg, "field": field}] {
          container := input.review.object.spec[field][_]
          mem_orig := container.resources.limits.memory
          mem := canonify_mem(mem_orig)
          max_mem_orig := input.parameters.memory
          max_mem := canonify_mem(max_mem_orig)
          mem > max_mem
          msg := sprintf("container <%v> memory limit <%v> is higher than the maximum allowed of <%v>", [container.name, mem_orig, max_mem_orig])
        }
```

And according to this template, I also created my constraint to limit deployments which requires more than 2 cores per pod or more than 4G memory. I also set the scope for this constraint, hello-goose namespace.

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-cpu-limit
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: 
      - hello-goose
  parameters:
    cpu: "2000m"
    memory: "4G"
```

Similarly, for the last scenario, a deployment can be applied to a list of namespaces by creating a constraint template and constraint which we are going to list the namespaces allowed or not allowed. 
