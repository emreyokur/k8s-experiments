#!/usr/bin/bash

set -x

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install consul

declare AGENTS=("192.168.7.111")
declare DC="dc1"

export ENCRYPT=$(consul keygen)
#scp consul-agent-ca.pem <dc-name>-<server/client>-consul-<cert-number>.pem <dc-name>-<server/client>-consul-<cert-number>-key.pem <USER>@<PUBLIC_IP>:/etc/consul.d/
consul tls ca create
consul tls cert create -server -dc $DC

mkdir --parents /etc/consul.d
cp consul-agent-ca.pem $DC-server-consul-0-key.pem $DC-server-consul-0.pem /etc/consul.d/

for i in ${!AGENTS[@]}; do
  consul tls cert create -client -dc $DC
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$AGENTS[$i] mkdir --parents /etc/consul.d
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null consul-agent-ca.pem $DC-client-consul-$i-key.pem $DC-client-consul-$i.pem root@$AGENTS[$i]:/etc/consul.d/
done

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

