#!/usr/bin/bash

set -x

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install consul

#export ENCRYPT=$(consul keygen)

mkdir --parents /etc/consul.d

cat > consul.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/consul"
ca_file = "/etc/consul.d/consul-agent-ca.pem"
cert_file = "/etc/consul.d/dc1-client-consul-0.pem"
key_file = "/etc/consul.d/dc1-client-consul-0-key.pem"
verify_incoming = true
verify_outgoing = true
verify_server_hostname = true
retry_join = ["192.168.7.109"]
bind_addr = "{{ GetInterfaceIP \"eth0\" }}"
server = false
enable_script_checks = true
EOF

mv consul.hcl /etc/consul.d/

chown --recursive consul:consul /etc/consul.d
chmod 640 /etc/consul.d/consul.hcl

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
systemctl enable consul
systemctl start consul
systemctl status consul